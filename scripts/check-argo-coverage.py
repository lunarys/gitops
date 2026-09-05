#!/usr/bin/env python3
"""Check that the PR helm-diff's view of this repo matches what Argo actually deploys.

The PR diff workflow discovers work units from filename conventions (an app dir, an
optional <prefix>-app.yaml sibling, an optional overlay subdirectory). Those conventions
restate what the Argo Applications already declare, so they can drift -- and drift is
silent in the dangerous direction: a unit the workflow cannot see is never diffed, and
the check stays green.

Two sides are compared:

  * the deployed truth -- Applications rendered from the apps-wrapper chart
  * the workflow's view -- units enumerated from the filesystem and resolved by running
    `install.sh --dry-run`, which prints the release name, namespace and exact -f list

GATING (exit 1). Only the overlay contract, which is fully determined on both sides:

  1. every declared overlay (a subdirectory holding .overlay.yaml) is deployed by an
     Application of the declared name, and that Application's namespace, chart value
     files and sidecar value files match what install.sh --overlay would use
  2. every Application that reads values from a subdirectory of its chart path IS an
     overlay by definition, so it must have a marker -- this catches a forgotten
     .overlay.yaml, the one failure mode a hidden marker makes more likely

ADVISORY (exit 0, printed). Broader coverage of non-overlay apps. install.sh and the
apps-wrapper derive identity differently in places that predate this script (the wrapper
honours settings.namespace and settings.applicationName and supports a Chart- file
prefix; install.sh reads argo.namespace and derives names from the directory). Those
divergences are reported, not enforced, so that this check can gate the overlay contract
without first requiring install.sh to be reconciled with the wrapper.

Usage:
  check-argo-coverage.py --repo . --wrapper-chart 03_apps --env prod \
                         --app-roots "03_apps/apps 02_bootstrap"
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys

MARKER = ".overlay.yaml"


def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def render_applications(repo, chart, env):
    """Applications from the wrapper chart, as parsed dicts. Uses yq for YAML->JSON so
    this needs no python yaml module (the workflow already installs yq)."""
    chart_dir = os.path.join(repo, chart)
    if not os.path.isdir(chart_dir):
        return None
    values = [os.path.join(chart_dir, "values.yaml")]
    for candidate in (f"values-{env}.yaml", f"values-{env}-apps.yaml"):
        p = os.path.join(chart_dir, candidate)
        if os.path.exists(p):
            values.append(p)

    cmd = ["helm", "template", "apps", chart_dir]
    for v in values:
        cmd += ["-f", v]
    rc, out, err = run(cmd, cwd=repo)
    if rc != 0:
        sys.exit(f"error: rendering {chart} failed:\n{err.strip()}")

    rc, js, err = subprocess.run(
        ["yq", "-o=json", "-I=0", "select(.kind == \"Application\")", "-"],
        input=out, capture_output=True, text=True
    ), None, None
    if rc.returncode != 0:
        sys.exit(f"error: yq failed to parse rendered output:\n{rc.stderr.strip()}")

    apps = {}
    for line in rc.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        d = json.loads(line)
        sources = d["spec"].get("sources") or []
        chart_src = next((s for s in sources if s.get("path") or s.get("chart")), {})
        apps[d["metadata"]["name"]] = {
            "namespace": d["spec"]["destination"].get("namespace"),
            "path": chart_src.get("path"),
            "chart": chart_src.get("chart"),
            "chart_values": ((chart_src.get("helm") or {}).get("valueFiles") or []),
            "chart_ignore_missing": bool(
                (chart_src.get("helm") or {}).get("ignoreMissingValueFiles")),
            "sidecar_values": [
                v for s in sources if s is not chart_src
                for v in ((s.get("helm") or {}).get("valueFiles") or [])
            ],
            "sidecar_ignore_missing": any(
                (s.get("helm") or {}).get("ignoreMissingValueFiles")
                for s in sources if s is not chart_src),
        }
    return apps


def normalise(value_files, app_dir, repo=None, ignore_missing=False):
    """Value file paths as seen from the app directory. Argo writes sidecar paths as
    '$repo/<app dir>/<file>' and chart-source paths relative to the source path.

    Two Argo-isms have no install.sh counterpart and are dropped rather than reported:
      * $privateRepo entries live in a second repository install.sh never reads
      * with ignoreMissingValueFiles, a listed file that does not exist contributes
        nothing, so Argo listing it and install.sh omitting it are equivalent
    """
    out = []
    for v in value_files:
        if v.startswith("$privateRepo/"):
            continue
        v = re.sub(r"^\$[A-Za-z_]+/", "", v)
        if app_dir and v.startswith(app_dir + "/"):
            v = v[len(app_dir) + 1:]
        if ignore_missing and repo is not None:
            if not os.path.exists(os.path.join(repo, app_dir, v)):
                continue
        out.append(v)
    return out


def app_dir_of(app, app_roots):
    """The repo-relative app directory an Application's chart source reads from."""
    if app["path"] and any(app["path"] == r or app["path"].startswith(r + "/")
                           for r in app_roots):
        return app["path"]
    # app.yaml apps reference an external chart; the app dir shows up in the $repo paths.
    for v in app["chart_values"] + app["sidecar_values"]:
        m = re.match(r"^\$[A-Za-z_]+/(.+)/[^/]+$", v)
        if m:
            candidate = m.group(1)
            for r in app_roots:
                if candidate == r or candidate.startswith(r + "/"):
                    # strip a trailing overlay segment, if any
                    parts = candidate.split("/")
                    while len(parts) > len(r.split("/")) + 1:
                        parts.pop()
                    return "/".join(parts)
    return None


def declared_overlays(repo, app_roots):
    """(app_dir, overlay_dir, declared_name) for every marker in the tree."""
    found = []
    for root in app_roots:
        root_dir = os.path.join(repo, root)
        if not os.path.isdir(root_dir):
            continue
        for app in sorted(os.listdir(root_dir)):
            app_path = os.path.join(root_dir, app)
            if not os.path.isdir(app_path):
                continue
            for sub in sorted(os.listdir(app_path)):
                marker = os.path.join(app_path, sub, MARKER)
                if not os.path.isfile(marker):
                    continue
                rc, name, err = run(["yq", "-r", '.name // ""', marker])
                found.append((f"{root}/{app}", sub, name.strip()))
    return found


def enumerate_units(repo, app_roots):
    units = []
    for root in app_roots:
        root_dir = os.path.join(repo, root)
        if not os.path.isdir(root_dir):
            continue
        for app in sorted(os.listdir(root_dir)):
            app_dir = os.path.join(root_dir, app)
            if not os.path.isdir(app_dir):
                continue
            entries = sorted(os.listdir(app_dir))
            if "app.yaml" in entries or "Chart.yaml" in entries:
                units.append((f"{root}/{app}", "", ""))
            for e in entries:
                if e.endswith("-app.yaml"):
                    units.append((f"{root}/{app}", e[: -len("-app.yaml")], ""))
            for e in entries:
                if os.path.isfile(os.path.join(app_dir, e, MARKER)):
                    units.append((f"{root}/{app}", "", e))
    return units


UPGRADE_RE = re.compile(r'helm upgrade --install "([^"]+)".*?--namespace "([^"]+)"(.*)$')


def resolve_unit(repo, unit, env, install_script="scripts/install.sh"):
    """Identity and -f lists install.sh would use, read back from --dry-run."""
    app_dir, prefix, overlay = unit
    cmd = ["bash", install_script, "--dry-run", "--env", env,
           "--include-all", "-d", app_dir]
    if prefix:
        cmd += ["--prefix", prefix]
    if overlay:
        cmd += ["--overlay", overlay]
    rc, out, err = run(cmd, cwd=repo)
    if rc != 0:
        tail = err.strip().splitlines()
        return None, f"install.sh failed: {tail[-1] if tail else 'rc=%d' % rc}"

    chart, sidecars = None, []
    for line in out.splitlines():
        m = UPGRADE_RE.search(line.strip())
        if not m:
            continue
        name, namespace, tail = m.groups()
        toks = shlex.split(tail)
        files = [toks[i + 1] for i, t in enumerate(toks) if t == "-f"]
        files = [f[2:] if f.startswith("./") else f for f in files]
        if chart is None:
            chart = {"name": name, "namespace": namespace, "value_files": files}
        else:
            sidecars.extend(files)
    if chart is None:
        return None, "install.sh --dry-run printed no helm upgrade line"
    chart["sidecar_values"] = sidecars
    return chart, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default=".")
    ap.add_argument("--wrapper-chart", default="03_apps")
    ap.add_argument("--env", default="prod")
    ap.add_argument("--app-roots", default="03_apps/apps 02_bootstrap")
    ap.add_argument("--install-script", default="scripts/install.sh",
                    help="install.sh to resolve units with; relative to --repo, or "
                         "absolute when it comes from a separate checkout")
    args = ap.parse_args()

    repo = os.path.abspath(args.repo)
    app_roots = args.app_roots.split()
    install_script = args.install_script
    if os.path.isabs(install_script):
        pass
    elif not os.path.exists(os.path.join(repo, install_script)):
        sys.exit(f"error: install script not found: {install_script} (in {repo})")

    apps = render_applications(repo, args.wrapper_chart, args.env)
    if apps is None:
        print(f"{args.wrapper_chart} not present -- nothing to reconcile, skipping.")
        return
    overlays = declared_overlays(repo, app_roots)
    units = enumerate_units(repo, app_roots)

    errors, advisory = [], []

    # --- GATE 1: every declared overlay is deployed, and matches ---
    for app_dir, sub, name in overlays:
        where = f"{app_dir}/{sub}/{MARKER}"
        if not name:
            errors.append(f"{where} declares no 'name'")
            continue
        if name not in apps:
            errors.append(
                f"{where} declares name '{name}', but no Application of that name is "
                f"deployed -- the PR diff would render an overlay Argo does not deploy")
            continue
        app = apps[name]
        info, err = resolve_unit(repo, (app_dir, "", sub), args.env, install_script)
        if err:
            errors.append(f"{where}: {err}")
            continue
        if info["namespace"] != app["namespace"]:
            errors.append(
                f"overlay '{name}': namespace mismatch -- Argo '{app['namespace']}', "
                f"install.sh '{info['namespace']}'")
        want = normalise(app["chart_values"], app_dir, repo,
                         app["chart_ignore_missing"])
        if info["value_files"] != want:
            errors.append(
                f"overlay '{name}': chart value files differ (order matters)\n"
                f"      Argo:       {want}\n"
                f"      install.sh: {info['value_files']}")
        want_side = sorted(set(normalise(
            app["sidecar_values"], app_dir, repo, app["sidecar_ignore_missing"])))
        got_side = sorted(set(info["sidecar_values"]))
        if want_side != got_side:
            errors.append(
                f"overlay '{name}': sidecar value files differ\n"
                f"      Argo:       {want_side}\n"
                f"      install.sh: {got_side}")

    # --- GATE 2: no undeclared overlay ---
    # An Application reading values from a subdirectory of its own chart path is an
    # overlay whether or not anyone wrote a marker for it.
    declared_pairs = {(d, s) for d, s, _ in overlays}
    for name, app in sorted(apps.items()):
        app_dir = app_dir_of(app, app_roots)
        if not app_dir:
            continue
        for v in normalise(app["chart_values"], app_dir):
            if "/" not in v:
                continue
            sub = v.split("/")[0]
            if (app_dir, sub) in declared_pairs:
                continue
            errors.append(
                f"Application '{name}' layers values from '{app_dir}/{sub}/', which is an "
                f"overlay, but {app_dir}/{sub}/{MARKER} is missing -- the PR diff would "
                f"attribute those changes to the parent release and report no diff")
            break

    # --- ADVISORY: broader coverage ---
    resolved = {}
    for unit in units:
        info, err = resolve_unit(repo, unit, args.env, install_script)
        if err:
            advisory.append(f"unit {unit} could not be resolved: {err}")
        else:
            resolved[info["name"]] = (unit, info)

    for name, app in sorted(apps.items()):
        app_dir = app_dir_of(app, app_roots)
        if not app_dir:
            advisory.append(f"Application '{name}': no app dir identified, not checked")
            continue
        if name not in resolved:
            advisory.append(
                f"Application '{name}' ({app_dir}) has no unit that resolves to this "
                f"release name -- install.sh and the wrapper derive it differently")
            continue
        _unit, info = resolved[name]
        if app["namespace"] and info["namespace"] != app["namespace"]:
            advisory.append(
                f"Application '{name}': namespace -- Argo '{app['namespace']}', "
                f"install.sh '{info['namespace']}'")
        want = normalise(app["chart_values"], app_dir, repo,
                         app["chart_ignore_missing"])
        if want and info["value_files"] != want:
            advisory.append(
                f"Application '{name}': chart value files -- Argo {want}, "
                f"install.sh {info['value_files']}")

    print(f"Applications: {len(apps)}   units: {len(units)}   "
          f"declared overlays: {len(overlays)}")
    for o in overlays:
        print(f"  overlay: {o[0]}/{o[1]} -> {o[2]}")
    if advisory:
        print(f"\nadvisory ({len(advisory)}) -- pre-existing install.sh/wrapper "
              f"divergence, not gated:")
        for a in advisory:
            print(f"  - {a}")
    if errors:
        print(f"\nERRORS ({len(errors)}) -- overlay contract violated:")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)
    print("\nOverlay contract holds: every declared overlay is deployed and matches, "
          "and no Application layers subdirectory values without a marker.")


if __name__ == "__main__":
    main()

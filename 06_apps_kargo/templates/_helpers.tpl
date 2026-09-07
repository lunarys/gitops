{{- /*
  A Kargo expression, written as `{{ include "kargo.expr" "vars.app" }}`.

  Helm parses `{{` wherever it appears in a template -- including inside YAML
  comments -- so a Kargo expression written literally would be read as a Helm
  action and fail. The escape is `${{ "{{" }} ... {{ "}}" }}`, which is
  unreadable repeated thirty times in one file. This says it once.

  Expressions are still wrapped in single YAML quotes at the point of use: an
  unquoted expression containing a ternary reads to a lenient YAML parser as
  complex-mapping-key syntax (`? key` / `: value`), silently turning the field
  into a map that Kargo rejects as "given: object". Quoting all of them rather
  than only the ternaries leaves no exception to remember. Inside a `|` block
  scalar the text is literal and neither rule applies.
*/ -}}
{{- define "kargo.expr" -}}
${{ "{{" }} {{ . }} {{ "}}" }}
{{- end -}}


{{- /*
  The three Stages differ in five things: name, shard, which values file the
  generator is rendered with, which directory the output lands in, and which
  branch it targets. Everything else -- the clone, the copy, the render, the PR
  and the Argo sync -- is identical, so it lives here once.

  Kargo expressions are written with the `kargo.expr` helper above -- see it for
  why they cannot be written literally, and for the quoting rule that goes with
  them. Every expression in a single-line field here is single-quoted; those
  inside a `|` block scalar are not, because the block is literal text.
*/ -}}
{{- define "apps-kargo.stage" -}}
{{- $root := .root -}}
{{- $repo := $root.Values.mainRepo -}}
{{- $generator := $root.Values.generatorRoot | trimSuffix "/" -}}
{{- $outDir := printf "%s/%s" $root.Values.renderedRoot .outDir -}}
{{- $alias := include "kargo.expr" "ctx.targetFreight.alias" -}}
{{- $freight := include "kargo.expr" "ctx.targetFreight.name" -}}
{{- $srcCommit := include "kargo.expr" (printf "commitFrom(%q).ID" $repo) -}}
{{- $srcBranch := include "kargo.expr" (printf "commitFrom(%q).Branch" $repo) -}}
{{- /*
  Conventional-commit subject. `chore` because the content is generated rather
  than authored, and the scope is the Stage -- which is also the name of the
  directory written and of the Argo CD Application that reconciles it.
*/ -}}
{{- $subject := printf "chore(%s): render %s" .name $alias -}}
{{- /*
  The PR title and description name NO Freight, and cannot. This branch is
  force-pushed, and git-open-pr adopts an already-open PR unchanged -- it looks
  one up and returns it, with no call that could edit its title or body. So
  anything per-promotion written here survives from the FIRST render on the
  branch and then describes a later render's diff. The commit is rebuilt every
  time and carries all of it; these two say only what is true of the branch.
*/ -}}
{{- $prTitle := printf "chore(%s): render onto %s" .name .targetBranch -}}
{{- $rendered := printf "Rendered %s with %s\ninto %s/, reconciled by Argo CD on %s." $generator .valuesFile $outDir .targetBranch -}}
{{- $provenance := printf "Freight: %s (%s)\nSource:  %s on %s" $alias $freight $srcCommit $srcBranch -}}
{{- /*
  Renders to nothing at all on an ordinary promotion, leaving a trailing blank
  line that git strips from the message; only a rollback says anything. A
  "Rollback: false" line on every commit would be noise.
*/ -}}
{{- $rollbackLine := include "kargo.expr" `ctx.meta.promotion.rollback ? "This is a rollback." : ""` -}}
{{- /*
  One fixed branch per Stage. See the comment on git-push below for why it is
  fixed rather than generated, and why force-pushing it is safe.
*/ -}}
{{- $branch := printf "%s%s" $root.Values.promotionBranchPrefix .name -}}
apiVersion: kargo.akuity.io/v1alpha1
kind: Stage
metadata:
  name: {{ .name }}
  namespace: {{ $root.Values.kargo.generatorProject }}
spec:
  # spec.shard, NOT the kargo.akuity.io/shard label. The Stage admission webhook
  # treats spec.shard as authoritative and derives the label from it, silently
  # stripping a label that does not match. Setting only the label means no
  # controller ever claims the Stage, with no error.
  #
  # A Stage runs on the shard of the cluster it changes. These Stages do change
  # a cluster: the argocd-update step below syncs that cluster's Argo CD, so a
  # Stage running elsewhere would push the git change and then fail to sync it.
  shard: {{ .shard }}
  requestedFreight:
    - origin:
        kind: Warehouse
        name: sources
      sources:
        # No gating between these Stages. They render structure -- an app added,
        # a setting changed -- and gating prod's structure behind test would mean
        # an offline test cluster blocks adding an app to prod.
        direct: true
  promotionTemplate:
    spec:
      steps:
        - uses: git-clone
          config:
            repoURL: {{ $repo }}
            checkout:
              - commit: '{{ $srcCommit }}'
                path: ./src
              - branch: {{ .targetBranch }}
                create: true
                path: ./out
        {{- /*
          Helm's .Files cannot read outside the chart directory, and the apps
          are a sibling of the generator. render.sh assembles the same workspace
          locally; without this step the scan finds no apps and the render is
          silently empty rather than failing.

          appsDir is this chart's own value, not a repository-wide one, and the
          helm-template step below passes the same string to the generator with
          --set: the step that writes the directory is the step that names it,
          so the two cannot drift.

          UNVERIFIED: that `copy` recurses into directories and creates the
          destination. The reference documents only inPath/outPath and says
          nothing about either. If it turns out to copy files only, this becomes
          a git-clone of the apps path into place instead.
        */}}
        - uses: copy
          config:
            inPath: ./src/{{ $root.Values.appRoot | trimSuffix "/" }}
            outPath: ./src/{{ $generator }}/{{ $root.Values.appsDir }}
        {{- /*
          Deleted before rendering so a removed app's resources disappear rather
          than lingering: the render only ever writes what currently exists, and
          without this the output is additive.

          strict: false because the directory does not exist on the first
          promotion, when the stage branch has just been created empty.
        */}}
        - uses: delete
          config:
            path: ./out/{{ $outDir }}
            strict: false
        - uses: helm-template
          config:
            path: ./src/{{ $generator }}
            outPath: ./out/{{ $outDir }}/resources.yaml
            # Cosmetic: verified that no generator template reads .Release.Name,
            # so this cannot affect the output. Matches render.sh so a local
            # render and a promotion render are invoked identically.
            releaseName: apps-generator
            valuesFiles:
              # The chart's own values.yaml is loaded automatically as the base
              # and is deliberately not repeated here -- passing it after the
              # shared file would let a generator default shadow a
              # repository-wide one.
              - ./src/gitops-values.yaml
              - ./src/{{ $generator }}/{{ .valuesFile }}
            # Where the copy step above put the app tree. Last word, so it wins
            # over the generator's own default.
            setValues:
              - key: appsDir
                value: {{ $root.Values.appsDir }}
            buildDependencies: false
            skipTests: true
        - uses: git-commit
          as: commit
          config:
            path: ./out
            message: |-{{ $subject | nindent 14 }}
              {{ $rendered | nindent 14 }}
              {{ $provenance | nindent 14 }}
              {{ $rollbackLine | nindent 14 }}
        {{- /*
          Pushed to a branch of its own and merged through a PR rather than
          straight onto the stage branch. Structural changes -- an app added or
          removed, a values file renamed, the generator itself changed -- are the
          ones most worth seeing as a rendered diff before they land, and for the
          prod apps with no test instance the rendered-config PR is the only gate
          there is. It is also what keeps a bad render out of the cluster
          altogether: argocd-update runs only once the PR has merged.

          ONE FIXED BRANCH PER STAGE, force-pushed, rather than Kargo's
          generateTargetBranch. A generated branch belongs to one Promotion, so
          re-rendering always means a second PR -- and the first PR's review
          comments are stranded on it -- while every aborted or no-op promotion
          leaves its branch behind.

          Force-pushing a fixed branch UPDATES the PR already under review
          instead: git-open-pr looks for an existing PR by base branch, head
          branch and head commit, and GitHub moves an open PR's head when its
          branch is force-pushed, so the PR it finds is that one -- same number,
          same comments. A PR that was already merged cannot be matched by
          mistake, its head commit being frozen at what merged rather than at
          what was just pushed.

          Forcing is safe here and nowhere else: this branch holds nothing but
          machine-written output, rebuilt from the stage branch on every
          promotion. A hand-written commit pushed onto it would be discarded --
          correctly, since editing rendered output is not a change; the source it
          was rendered from is.

          What this does NOT change is queueing. git-wait-for-pr below holds the
          promotion until the PR is resolved, and Kargo runs one Promotion per
          Stage at a time, so newer Freight waits as Pending rather than
          replacing what is in review. The PR gets updated when a waiting
          promotion is aborted and a newer one promoted in its place.
        */}}
        - uses: git-push
          as: push
          config:
            path: ./out
            targetBranch: {{ $branch }}
            force: true
        - uses: git-open-pr
          as: open-pr
          config:
            repoURL: {{ $repo }}
            # Set explicitly rather than inferred from the URL.
            provider: github
            sourceBranch: '{{ include "kargo.expr" "outputs.push.branch" }}'
            targetBranch: {{ .targetBranch }}
            title: {{ $prTitle | quote }}
            description: |-{{ $rendered | nindent 14 }}

              Everything under that path is machine-written, so this diff *is* the
              change: nothing renders again between merging this and the cluster acting
              on it. The promotion is parked in `git-wait-for-pr` until this PR is merged
              or closed.

              Which Freight this is, and which source commit it was rendered from, is in
              the commit message rather than here: a pull request's title and body are
              written once, when it opens, while this branch is force-pushed and this
              pull request reused if a later render supersedes the one below.
        {{- /*
          A render identical to the branch needs no special handling up to this
          point, and gets none: git-commit finds no diff, quietly makes no
          commit and outputs the existing HEAD; git-push then pushes a branch
          that matches its target; and git-open-pr, finding no difference
          between the two branches, reports Skipped rather than opening an empty
          PR.

          Only the steps AFTER it need the guard, and they need it explicitly --
          without it they fail trying to read a PR number that was never
          produced.
        */}}
        - if: '{{ include "kargo.expr" `status("open-pr") != "Skipped"` }}'
          uses: git-wait-for-pr
          as: wait-for-pr
          config:
            repoURL: {{ $repo }}
            provider: github
            prNumber: '{{ include "kargo.expr" `outputs["open-pr"].pr.id` }}'
        {{- /*
          Sync the Application that reconciles what was just written, pinned to
          the commit the merge produced. Without it the Stage would reference no
          Argo CD Application, so Kargo would have no health signal at all and
          "promoted" would mean only "the git push succeeded".

          Requires kargo.akuity.io/authorized-stage on that Application, which
          03_apps_bootstrap must set to <project>:<stage>.
        */}}
        - if: '{{ include "kargo.expr" `status("open-pr") != "Skipped"` }}'
          uses: argocd-update
          config:
            apps:
              - name: {{ .outDir }}
                namespace: {{ $root.Values.argo.namespace }}
                sources:
                  - repoURL: {{ $repo }}
                    desiredRevision: '{{ include "kargo.expr" `outputs["wait-for-pr"].commit` }}'
{{- end }}

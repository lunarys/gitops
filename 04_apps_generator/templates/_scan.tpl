{{- /*
  App detection. The only place that touches the file system.

  Returns a YAML document consumed by the emitters as:

    apps:
      cloudnative-pg:
        name: cloudnative-pg   # applicationName from settings.yaml, else the directory
        dir:  cloudnative-pg   # the directory on disk -- what Kargo filters paths by
        settings: {...}        # defaultSettings merged with the app's settings.yaml
        valuesFiles:
          base: [values.yaml, values-network.part.yaml]
          test: [values-test.yaml, values-secrets-test.part.yaml]
          prod: [values-prod.yaml]
    enabled:
      test: [bitwarden, ...]
      prod: [bitwarden, ...]

  Two things keep this small compared to what it replaced:

  1. One format, one app per directory. Every app is a Helm chart, so detection
     is a single glob. The old scanner had to handle app.yaml, Chart.yaml,
     <prefix>-app.yaml and Chart-<file>.yaml, and group several apps per
     directory.

  2. No file contents. No emitter reads a values or resource file -- they need
     only name, dir, settings and the values file NAMES. Collecting parsed file
     bodies existed to feed Argo's multi-source Application, which pre-rendering
     deleted.

  The enabled lists are read as FILES, not as Helm values. They stay two
  separate files that way, and one render can see both -- which the kargo
  render requires: a Warehouse is emitted for the union, and a prod Stage needs
  to know whether a test Stage exists before it can decide how to take Freight.
  As values they would collide on the `enabled` key and the last one would win.
*/ -}}
{{- define "apps-generator.scan" -}}
{{- $root := . -}}
{{- $appsDir := $root.Values.appsDir -}}
{{- $envs := list "test" "prod" -}}
{{- $apps := dict -}}
{{- range $path, $_ := $root.Files.Glob (printf "%s/*/Chart.yaml" $appsDir) }}
  {{- $dir := index (regexSplit "/" $path -1) 1 -}}
  {{- $settings := mergeOverwrite (dict) (deepCopy $root.Values.defaultSettings) -}}
  {{- with $root.Files.Get (printf "%s/%s/settings.yaml" $appsDir $dir) }}
    {{- $settings = mergeOverwrite (dict) (deepCopy $root.Values.defaultSettings) (. | fromYaml) -}}
  {{- end }}
  {{- $valuesFiles := include "apps-generator.valuesFiles" (dict "root" $root "dir" $dir "envs" $envs) | fromYaml -}}
  {{- $_ := set $apps $dir (dict "name" (dig "applicationName" $dir $settings) "dir" $dir "settings" $settings "valuesFiles" $valuesFiles) -}}
{{- end }}
{{- $enabled := dict -}}
{{- range $env := $envs }}
  {{- $doc := $root.Files.Get (printf "%s/apps-%s.yaml" $appsDir $env) | fromYaml -}}
  {{- $_ := set $enabled $env (dig "enabled" (list) $doc) -}}
{{- end }}
{{ dict "apps" $apps "enabled" $enabled | toYaml }}
{{- end }}


{{- /*
  Values file discovery for one app directory.

  The convention:

    values.yaml                        base, always first
    values-<env>.yaml                  environment overlay
    values-<label>.part.yaml           a fragment
    values-<label>-<env>.part.yaml     environment variant of a fragment

  <label> is a free human name bound to nothing. What a fragment applies to is
  the top-level key INSIDE it -- values-network.part.yaml contains
  `networkpolicy:`. Deliberately not matched against Chart.yaml dependency
  names: that would mean an `alias:` change forces a file rename, and the check
  could never be complete anyway, because a merged chart's values also carry the
  parent chart's own top-level keys.

  `.part.` rather than bare `values-<label>.yaml` so a fragment can never be
  mistaken for an environment overlay. Without the marker the two are told apart
  only by knowing the environment names, and adding a third environment later
  would silently reinterpret any fragment that happened to share its name.

  Anything else ending in .yaml is an error rather than an ignored file. A
  values file that is silently not passed is exactly the failure this whole
  design is trying to remove.

  Returns:  {base: [...], test: [...], prod: [...]}

  Order within each list is the layering order, and is deterministic:
  .Files.Glob returns a map, and Go templates range over map keys sorted.
*/ -}}
{{- define "apps-generator.valuesFiles" -}}
{{- $root := .root -}}
{{- $dir := .dir -}}
{{- $envs := .envs -}}
{{- $appsDir := $root.Values.appsDir -}}
{{- $base := list -}}
{{- $parts := list -}}
{{- $envFile := dict -}}
{{- $envParts := dict -}}
{{- range $e := $envs }}{{- $_ := set $envParts $e (list) -}}{{- end }}
{{- range $path, $_ := $root.Files.Glob (printf "%s/%s/*.yaml" $appsDir $dir) }}
  {{- $f := base $path -}}
  {{- if has $f (list "Chart.yaml" "settings.yaml") -}}
    {{- /* chart metadata, not values */ -}}
  {{- else if eq $f "values.yaml" -}}
    {{- $base = list $f -}}
  {{- else if hasSuffix ".part.yaml" $f -}}
    {{- if not (hasPrefix "values-" $f) -}}
      {{- fail (printf "%s/%s: fragment %q must be named values-<label>[-<env>].part.yaml" $appsDir $dir $f) -}}
    {{- end -}}
    {{- $stem := $f | trimSuffix ".part.yaml" | trimPrefix "values-" -}}
    {{- $env := "" -}}
    {{- range $e := $envs -}}
      {{- if hasSuffix (printf "-%s" $e) $stem -}}{{- $env = $e -}}{{- end -}}
    {{- end -}}
    {{- if $env -}}
      {{- $_ := set $envParts $env (append (index $envParts $env) $f) -}}
    {{- else -}}
      {{- $parts = append $parts $f -}}
    {{- end -}}
  {{- else if hasPrefix "values-" $f -}}
    {{- $stem := $f | trimSuffix ".yaml" | trimPrefix "values-" -}}
    {{- if has $stem $envs -}}
      {{- $_ := set $envFile $stem $f -}}
    {{- else -}}
      {{- fail (printf "%s/%s: %q is neither an environment overlay nor a fragment. Environments are %v; a fragment must end in .part.yaml" $appsDir $dir $f $envs) -}}
    {{- end -}}
  {{- else -}}
    {{- /*
      Not a values file -- ignored rather than rejected.

      The generator polices files that LOOK like values files, not the whole
      directory. Rejecting every unrecognised .yaml would police files that are
      none of its business, and would hard-fail on any directory still holding
      pre-conversion layout, which makes app-by-app migration impossible.

      Both realistic mistakes are still caught above: a fragment that forgot the
      values- prefix, and a values-<x>.yaml whose <x> is not an environment.
    */ -}}
  {{- end -}}
{{- end }}
{{- /*
  Empty lists are omitted rather than emitted. toYaml renders an empty list as
  `null`, which survives the fromYaml round trip as a present-but-nil key -- so
  `dig` finds the key, returns nil rather than its default, and the consumer
  gets a nil where it expected a list.
*/ -}}
{{- $out := dict -}}
{{- $all := concat $base $parts -}}
{{- if $all -}}{{- $_ := set $out "base" $all -}}{{- end -}}
{{- range $e := $envs -}}
  {{- $l := list -}}
  {{- if hasKey $envFile $e -}}{{- $l = append $l (index $envFile $e) -}}{{- end -}}
  {{- $l = concat $l (index $envParts $e) -}}
  {{- if $l -}}{{- $_ := set $out $e $l -}}{{- end -}}
{{- end -}}
{{ $out | toYaml }}
{{- end }}

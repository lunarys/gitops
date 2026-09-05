{{- /*
  App detection. The only place that touches the file system.

  Returns a YAML document consumed by the emitters as:

    apps:
      bitwarden:
        name: bitwarden      # applicationName from settings.yaml, else the directory
        dir:  bitwarden      # the directory on disk -- what Kargo filters paths by
        settings: {...}      # defaultSettings merged with the app's settings.yaml
    enabled:
      test: [bitwarden, ...]
      prod: [bitwarden, ...]

  Two things keep this small compared to what it replaced:

  1. One format, one app per directory. Every app is a Helm chart, so detection
     is a single glob. The old scanner had to handle app.yaml, Chart.yaml,
     <prefix>-app.yaml and Chart-<file>.yaml, and group several apps per
     directory.

  2. No file contents. No emitter reads a values or resource file any more --
     they need only name, dir and settings. Collecting parsed file bodies
     existed to feed Argo's multi-source Application, which pre-rendering
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
{{- $apps := dict -}}
{{- range $path, $_ := $root.Files.Glob (printf "%s/*/Chart.yaml" $appsDir) }}
  {{- $dir := index (regexSplit "/" $path -1) 1 -}}
  {{- $settings := mergeOverwrite (dict) (deepCopy $root.Values.defaultSettings) -}}
  {{- with $root.Files.Get (printf "%s/%s/settings.yaml" $appsDir $dir) }}
    {{- $settings = mergeOverwrite (dict) (deepCopy $root.Values.defaultSettings) (. | fromYaml) -}}
  {{- end }}
  {{- $_ := set $apps $dir (dict "name" (dig "applicationName" $dir $settings) "dir" $dir "settings" $settings) -}}
{{- end }}
{{- $enabled := dict -}}
{{- range $env := list "test" "prod" }}
  {{- $doc := $root.Files.Get (printf "%s/apps-%s.yaml" $appsDir $env) | fromYaml -}}
  {{- $_ := set $enabled $env (dig "enabled" (list) $doc) -}}
{{- end }}
{{ dict "apps" $apps "enabled" $enabled | toYaml }}
{{- end }}

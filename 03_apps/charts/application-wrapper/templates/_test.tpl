{{- define "apps-wrapper.test" -}}
{{- if .Values.renderTest }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-test
data:
  test: |
    {{- $apps := dict -}}
    {{- $allfiles := .Files.Glob "apps/*/**" -}}
    {{- $appYamls := .Files.Glob "apps/*/app.yaml" }}
    {{- range $path, $_ := $appYamls }}
      {{- $dir := dir $path }}
      {{- $name := base $dir }}
      {{- $files := dict }}
      {{- range $filePath, $fileContent := $allfiles }}
        {{- if hasPrefix $dir $filePath }}
          {{- $filePathStripped := trimPrefix (printf "%s/" $dir) $filePath }}
          {{- $_ := set $files $filePathStripped $fileContent }}
        {{- end }}
      {{- end }}
      {{- $_ := set $apps $name (dict "name" $name "dir" $dir "files" $files "variant" "app") }}
    {{- end }}
    {{- $chartYamls := .Files.Glob "apps/*/Chart.yaml" }}
    {{- range $path, $_ := $chartYamls }}
      {{- $dir := dir $path }}
      {{- $name := base $dir }}
      {{- $files := dict }}
      {{- range $filePath, $fileContent := $allfiles }}
        {{- if hasPrefix $dir $filePath }}
          {{- $filePathStripped := trimPrefix (printf "%s/" $dir) $filePath }}
          {{- $_ := set $files $filePathStripped $fileContent }}
        {{- end }}
      {{- end }}
      {{- $_ := set $apps $name (dict "name" $name "dir" $dir "files" $files "variant" "chart") }}
    {{- end }}
    {{- toYaml $apps | nindent 4 }}
{{- end }}
{{- end }}

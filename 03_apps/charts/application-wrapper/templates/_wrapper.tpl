{{- define "apps-wrapper.wrapper" }}
{{- /* Collect all applications and charts from the apps/ directory */ -}}
{{- $apps := dict -}}
{{- $allfiles := .Files.Glob "apps/*/**" -}}
{{- $appYamls := .Files.Glob "apps/*/*app.yaml" }}
{{- $chartYamls := .Files.Glob "apps/*/Chart.yaml" }}
{{- $defaultSettings := .Values.defaultSettings }}
{{- /* Get a concatenated list of app.yaml and Chart.yaml. This workaround is required, as 'keys' does not work with .Files.Glob */ -}}
{{- $appsAndCharts := list }}
{{- range $path, $_ := $appYamls }}
  {{- $appsAndCharts = append $appsAndCharts $path }}
{{- end }}
{{- range $path, $_ := $chartYamls }}
  {{- $appsAndCharts = append $appsAndCharts $path }}
{{- end }}
{{- /* Group all applications from the same directory */ -}}
{{- $groupedApps := dict }}
{{- range $path := $appsAndCharts }}
  {{- $pathSplit := regexSplit "/" $path -1 }}
  {{- $groupName := index $pathSplit 1 }}
  {{- if not (hasKey $groupedApps $groupName) }}
    {{- $_ := set $groupedApps $groupName (list) }}
  {{- end }}
  {{- $_ := set $groupedApps $groupName (append (index $groupedApps $groupName) $path) }}
{{- end }}
{{- /* Create a dictionary of apps, nested in projects */ -}}
{{- range $group, $paths := $groupedApps }}
  {{- $projectDir := printf "apps/%s" $group }}
  {{- /* Get a list of files in the project directory, strip the project path prefix */ -}}
  {{- $files := dict }}
  {{- range $filePath, $fileContent := $allfiles }}
    {{- if hasPrefix $projectDir $filePath }}
      {{- $filePathStripped := trimPrefix (printf "%s/" $projectDir) $filePath }}
      {{- $_ := set $files $filePathStripped ($.Files.Get $filePath | fromYaml) }}
    {{- end }}
  {{- end }}
  {{- /* Find optional settings */ -}}
  {{- $settings := $defaultSettings }}
  {{- if hasKey $files "settings.yaml" }}
    {{- $settings = merge (index $files "settings.yaml") $settings }}
  {{- end }}
  {{- if hasKey $files "app.yaml" }}
    {{- $appSettings := index $files "app.yaml" "settings" | default (dict) }}
    {{- $settings = merge $appSettings $settings }}
  {{- end }}
  {{- /* Create a project entry in the apps dictionary */ -}}
  {{- $projectApps := dict -}}
  {{- $project := dict "name" $group "dir" $projectDir "settings" $settings "apps" $projectApps }}
  {{- $_ := set $apps $group $project }}
  {{- /* Now add each application in the group to the projectApps dictionary */ -}}
  {{- range $path := $paths }}
    {{- $fileName := base $path }}
    {{- $name := $group }}
    {{- $prefix := "" }}
    {{- $appFiles := dict }}
    {{- /* Chart.yaml variant is simpler: Prefix may only (optionally) be Chart- and there may be a Chart-settings.yaml file */ -}}
    {{- if eq $fileName "Chart.yaml" }}
      {{- /* Get app-specific settings and merge them with the project settings */ -}}
      {{- if hasKey $files "Chart-settings.yaml" }}
        {{- $chartSettings := index $files "Chart-settings.yaml" | default (dict) }}
        {{- $settings = merge $chartSettings $defaultSettings $settings }}
      {{- end }}
      {{- /* The files for Chart.yaml apps can be prefixed with Chart-, check values.yaml if this is the case */ -}}
      {{- if hasKey $files "Chart-values.yaml" }}
        {{- $prefix = "Chart-" -}}
        {{- /* Filtering files for the prefix would remove Chart.yaml from the list, to add it here */ -}}
        {{- $_ := set $appFiles "Chart.yaml" (index $files "Chart.yaml") -}}
      {{- end }}
    {{- else -}}
      {{- /* app.yaml may have a prefix in order to place multiple in the same directory */ -}}
      {{- if ne $fileName "app.yaml" }}
        {{- $prefix = trimSuffix "app.yaml" $fileName }}
        {{- $name = trimSuffix "-" $prefix }}
      {{- end }}
      {{- /* Get app-specific settings and merge them with the project settings */ -}}
      {{- $appSettings := index $files $fileName "settings" | default (dict) }}
      {{- $settings := merge $appSettings $defaultSettings $settings }}
    {{- end }}
    {{- /* In order to facilitate processing in later steps, strip the prefix from filenames and filter for files that have the prefix */ -}}
    {{- if $prefix }}
      {{- range $filePath, $fileContent := $files }}
        {{- if hasPrefix $prefix $filePath }}
          {{- $_ := set $appFiles (trimPrefix $prefix $filePath) $fileContent }}
        {{- end }}
      {{- end }}
    {{- else }}
      {{- $appFiles = $files }}
    {{- end }}
    {{- /* Name can be overwritten in the settings*/ -}}
    {{- if hasKey $settings "applicationName" }}
      {{- $name = $settings.applicationName }}
    {{- end }}
    {{- /* Finally, construct the app dict */ -}}
    {{- $app := dict "name" $name "dir" $projectDir "prefix" $prefix "files" $appFiles "settings" $settings "project" $group }}
    {{- $_ := set $projectApps $name $app }}
  {{- end }}
{{- end }}
{{/*
Structure of the apps dictionary:
  {
    "app1": {
      "name": "app1",
      "dir": "apps/app1",
      "settings": {},  # from app.yaml or settings.yaml
      "apps": {
        "app1": {
          "name": "app1",
          "project": "app1",
          "dir": "apps/app1",
          "prefix": "",
          "files": {
            "file1.yaml": "<content as dict>",
            "app.yaml": "<content as dict>"
          },
          "settings": {}  # from app.yaml
        }
      }
    },
    "chart1": {
      "name": "chart1",
      "dir": "apps/chart1",
      "settings": {}  # from settings.yaml or app.yaml[settings], e.g. namespace
      "apps": {
        "chart1": {
          "name": "chart1",
          "project": "chart1",
          "dir": "apps/chart1",
          "prefix": "",
          "files": {
            "Chart.yaml": "<content as dict>",
            "values.yaml": "<content as dict>"
          },
          "settings": {}  # from settings.yaml, Chart-settings.yaml or app.yaml[settings], e.g. namespace
        }
      }
    },
    "multiapp": {
      "name: "apps",
      "dir: "apps/mutliapp",
      "settings": {},  # from settings.yaml or app.yaml[settings]
      "apps": {
        "multiapp": {
          "name": "multiapp",
          "project": "multiapp",
          "dir": "apps/multiapp",
          "prefix": "",
          "files": {
            "app.yaml": "<content as dict>",
            "values.yaml": "<content as dict>"
          },
          "settings": {}  # from settings.yaml or app.yaml[settings]
        },
        "nginx": {
          "name": "nginx",
          "project": "multiapp",
          "dir": "apps/multiapp",
          "prefix": "nginx-"
          "files": {
            "app.yaml": "<content as dict, removed filename prefix>",
            "values.yaml": "<content as dict, removed filename prefix>"
          }
          "settings": {}  # merged from nginx-app.yaml and app.yaml[settings] and settings.yaml}
        }
      }
    }
  }
*/}}
{{- range $project, $settings := $apps }}
  {{- if or (not (hasKey $.Values "enabled")) (has $project $.Values.enabled) }}
  {{- /* Template the project */}}
---
{{ include "apps-wrapper.project" (dict "settings" $settings "root" $) }}
    {{- /* Template each application in the project */}}
    {{- range $app, $appSettings := (index $settings "apps") }}
---
{{ include "apps-wrapper.application" (dict "settings" $appSettings "root" $) }}
    {{- end }}
  {{- end }}
{{- end }}
{{- end }}
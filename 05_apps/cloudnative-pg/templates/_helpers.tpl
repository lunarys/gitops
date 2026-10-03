{{- define "postgresdb.cnpg.clusterName" -}}
{{- if .Values.postgres.clusterNameOverride -}}
{{- .Values.postgres.clusterNameOverride -}}
{{- else -}}
postgresdb-gen-{{ .Values.clusterGeneration | required "clusterGeneration is required when postgres.clusterNameOverride is not set" }}
{{- end -}}
{{- end }}

{{- define "postgresdb.cnpg.previousClusterName" -}}
{{- if .Values.restore.clusterNameOverride -}}
{{- .Values.restore.clusterNameOverride -}}
{{- else -}}
postgresdb-gen-{{ .Values.clusterPreviousGeneration | required "clusterPreviousGeneration is required when restore.clusterNameOverride is not set" }}
{{- end -}}
{{- end }}

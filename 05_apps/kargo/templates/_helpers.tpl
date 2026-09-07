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

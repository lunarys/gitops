#!/usr/bin/env bash
# recreate-pki.sh — Recreate step-ca root + intermediate CA
#
# Uses Docker (smallstep/step-ca image) — no local step CLI required.
# Updates GitOps files in-place and prints Bitwarden entries to update.
#
# Usage: ./recreate-pki.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_CM="$SCRIPT_DIR/resources-prod/certs-configmap.yaml"
CONFIG_CM="$SCRIPT_DIR/resources-prod/config-configmap.yaml"
ISSUER_YAML="$SCRIPT_DIR/resources-prod/step-cert-issuer.yaml"

# Match the image to what the Helm chart uses; override with STEP_CA_IMAGE env var
STEP_CA_IMAGE="${STEP_CA_IMAGE:-smallstep/step-ca:latest}"
DOCKER="${DOCKER:-sudo docker}"

# ── Helpers ──────────────────────────────────────────────────────────────────

die() { echo "ERROR: $*" >&2; exit 1; }

check_deps() {
  local missing=()
  for cmd in sudo docker yq base64 openssl; do
    command -v "$cmd" &>/dev/null || missing+=("$cmd")
  done
  [[ ${#missing[@]} -eq 0 ]] || die "Missing required tools: ${missing[*]}"
}

# prompt VAR_NAME "Question" "default value"
prompt() {
  local -n _ref="$1"
  local question="$2" default="$3" value
  read -r -p "  $question [$default]: " value
  _ref="${value:-$default}"
}

# prompt_secret VAR_NAME "Question"
prompt_secret() {
  local -n _ref="$1"
  local question="$2" value
  #read -rs -p "  $question: " value
  read -r -p "  $question: " value
  echo
  _ref="$value"
}

header() { echo ""; echo "=== $* ==="; }

# ── Main ──────────────────────────────────────────────────────────────────────

main() {
  check_deps

  cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║              step-ca PKI Recreation Script                   ║
╚══════════════════════════════════════════════════════════════╝

This will generate a new root CA and intermediate CA, update the
GitOps YAML files, and print the secrets you need to update in
Bitwarden.

WARNING: Recreating the PKI invalidates ALL existing certificates.
         cert-manager will need to renew every certificate.

EOF
  read -r -p "Continue? [y/N]: " confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  # ── Read current config for defaults ──────────────────────────────────────

  local current_ca_json current_defaults_json
  current_ca_json=$(yq '.data."ca.json"' "$CONFIG_CM")
  current_defaults_json=$(yq '.data."defaults.json"' "$CONFIG_CM")

  local default_provisioner default_dns
  default_provisioner=$(yq -p=json '.authority.provisioners[] | select(.type == "JWK") | .name' <<< "$current_ca_json")
  default_dns=$(yq -p=json '.dnsNames | join(",")' <<< "$current_ca_json")

  # ── Configuration prompts ─────────────────────────────────────────────────

  header "Configuration"
  echo "  (Press Enter to keep current value shown in brackets)"
  echo ""

  local CA_NAME CA_DNS PROVISIONER_NAME ALLOWED_DOMAINS CURVE
  prompt CA_NAME           "CA display name"               "step-ca.svc.elda"
  prompt CA_DNS            "CA DNS names (comma-separated)" "$default_dns"
  prompt PROVISIONER_NAME  "JWK provisioner name"           "$default_provisioner"
  prompt ALLOWED_DOMAINS   "Name Constraint domains (comma-separated, e.g. .elda,.local)" ".elda"
  prompt CURVE             "EC curve [P-256 / P-384]"       "P-384"

  [[ "$CURVE" == "P-256" || "$CURVE" == "P-384" ]] || die "Curve must be P-256 or P-384"

  # ── Passwords ──────────────────────────────────────────────────────────────

  header "Passwords"
  echo "  1) Generate random passwords (recommended)"
  echo "  2) Enter passwords manually"
  echo ""
  local pw_choice
  read -r -p "  Choice [1/2]: " pw_choice

  local CA_PASSWORD PROV_PASSWORD
  if [[ "$pw_choice" == "2" ]]; then
    prompt_secret CA_PASSWORD   "CA key password"
    prompt_secret PROV_PASSWORD "Provisioner password"
    [[ -n "$CA_PASSWORD" && -n "$PROV_PASSWORD" ]] || die "Passwords cannot be empty"
  else
    CA_PASSWORD=$(openssl rand -base64 50)
    PROV_PASSWORD=$(openssl rand -base64 50)
    echo "  Generated random passwords."
  fi

  # ── Temp directory ────────────────────────────────────────────────────────

  local workdir
  workdir=$(mktemp -d)
  # shellcheck disable=SC2064
  trap "rm -rf '$workdir'" EXIT

  # ── Generate PKI via Docker ───────────────────────────────────────────────

  header "Generating PKI (via Docker: $STEP_CA_IMAGE)"

  # Write password files into bind-mounted workdir; deleted right after docker runs
  printf '%s' "$CA_PASSWORD"   > "$workdir/ca-password"
  printf '%s' "$PROV_PASSWORD" > "$workdir/prov-password"

  # Build Name Constraints template (step ca init doesn't support --name-constraint;
  # we generate the root CA separately via step certificate create with a template)
  # Phase 1 writes root cert+key to staging paths; step ca init will copy them
  # into its own certs/ and secrets/ directories (avoiding an overwrite conflict)
  local nc_json_array
  nc_json_array=$(
    IFS=','
    read -ra nc_domains <<< "$ALLOWED_DOMAINS"
    first=true
    for domain in "${nc_domains[@]}"; do
      domain="${domain// /}"
      [[ -z "$domain" ]] && continue
      $first || printf ','
      printf '"%s"' "$domain"
      first=false
    done
  )
  # --profile and --template are mutually exclusive in step certificate create.
  # Write a complete root-CA template that includes both the CA profile fields
  # (self-signed, isCA, keyUsage) and the Name Constraints extension.
  # .Subject is populated by step from the first CLI argument.
  cat > "$workdir/nc-template.json" << TMPL
{
  "subject": {{ toJson .Subject }},
  "issuer": {{ toJson .Subject }},
  "keyUsage": ["certSign", "crlSign"],
  "basicConstraints": {
    "isCA": true,
    "maxPathLen": 1
  },
  "nameConstraints": {
    "critical": true,
    "permittedDNSDomains": [$nc_json_array]
  }
}
TMPL

  # Phase 1: create root CA with Name Constraints + chosen key curve.
  # Write to staging paths (not certs/ or secrets/) so step ca init can copy
  # them into its own directory layout without hitting an overwrite prompt.
  local -a create_root_cmd=(
    $DOCKER run --rm
    -v "$workdir:/home/step"
    "$STEP_CA_IMAGE"
    step certificate create "$CA_NAME Root CA"
      /home/step/root_ca.crt
      /home/step/root_ca_key
      --kty EC
      --crv "$CURVE"
      --template /home/step/nc-template.json
      --password-file /home/step/ca-password
      --not-after 87600h
  )

  # Phase 2: init CA using existing root (generates intermediate + provisioner + config)
  # -t allocates a pseudo-TTY so step ca init can open /dev/tty for interactive prompts
  local -a init_cmd=(
    $DOCKER run --rm
    -t
    -v "$workdir:/home/step"
    "$STEP_CA_IMAGE"
    step ca init
      --name "$CA_NAME"
      --dns "$CA_DNS"
      --address ":9000"
      --provisioner "$PROVISIONER_NAME"
      --root /home/step/root_ca.crt
      --key /home/step/root_ca_key
      --key-password-file /home/step/ca-password
      --password-file /home/step/ca-password
      --provisioner-password-file /home/step/prov-password
      --deployment-type standalone
      --no-db
  )

  echo "  Phase 1 — root CA with Name Constraints:"
  echo "    ${create_root_cmd[*]}"
  echo ""
  echo "  Phase 2 — CA init using existing root:"
  echo "    ${init_cmd[*]}"
  echo ""
  read -r -p "  Proceed? [y/N]: " ok
  [[ "$ok" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

  # Ensure image is available
  $DOCKER image inspect "$STEP_CA_IMAGE" &>/dev/null \
    || $DOCKER pull "$STEP_CA_IMAGE"

  "${create_root_cmd[@]}"
  "${init_cmd[@]}"

  # Delete password files immediately
  rm -f "$workdir/ca-password" "$workdir/prov-password"

  # ── Extract generated artifacts ───────────────────────────────────────────

  header "Extracting generated values"

  local root_cert intermediate_cert root_key intermediate_key generated_ca_json
  root_cert=$(cat "$workdir/certs/root_ca.crt")
  intermediate_cert=$(cat "$workdir/certs/intermediate_ca.crt")
  root_key=$(cat "$workdir/root_ca_key")          # staging path; step ca init does not copy the root key
  intermediate_key=$(cat "$workdir/secrets/intermediate_ca_key")
  generated_ca_json=$(cat "$workdir/config/ca.json")

  # Get fingerprint of new root CA
  local fingerprint
  fingerprint=$($DOCKER run --rm \
    -v "$workdir:/home/step" \
    "$STEP_CA_IMAGE" \
    step certificate fingerprint /home/step/certs/root_ca.crt)

  # Extract new JWK provisioner from generated ca.json
  local new_jwk_provisioner
  new_jwk_provisioner=$(yq -p=json -o=json '.authority.provisioners[] | select(.type == "JWK")' <<< "$generated_ca_json")

  echo "  Root CA fingerprint : $fingerprint"
  echo "  JWK key ID          : $(yq -p=json '.key.kid' <<< "$new_jwk_provisioner")"

  # ── Build updated config values ────────────────────────────────────────────

  # Update ca.json: replace JWK provisioner entry (key + encryptedKey),
  # set provisioner name to user-chosen value, keep all other config unchanged
  # (ACME provisioner, x509 policy, tls settings, db config, dnsNames, etc.)
  local updated_ca_json
  updated_ca_json=$(new_jwk_provisioner="$new_jwk_provisioner" PROVISIONER_NAME="$PROVISIONER_NAME" \
    yq -p=json -o=json '
      (.authority.provisioners[] | select(.type == "JWK")) |=
        (strenv(new_jwk_provisioner) | from_json) + {"name": strenv(PROVISIONER_NAME)}
    ' <<< "$current_ca_json")

  # Update defaults.json: only the fingerprint changes
  local updated_defaults_json
  updated_defaults_json=$(fingerprint="$fingerprint" \
    yq -p=json -o=json '.fingerprint = strenv(fingerprint)' <<< "$current_defaults_json")

  # caBundle = base64-encoded root CA PEM (no line wrapping)
  local ca_bundle
  ca_bundle=$(echo "$root_cert" | base64 -w0)

  # ── Update GitOps files ────────────────────────────────────────────────────

  header "Updating GitOps files"

  echo "  resources-prod/certs-configmap.yaml ..."
  root_cert="$root_cert" intermediate_cert="$intermediate_cert" \
    yq -i '
      .data."root_ca.crt" = strenv(root_cert) |
      .data."intermediate_ca.crt" = strenv(intermediate_cert)
    ' "$CERTS_CM"

  echo "  resources-prod/config-configmap.yaml ..."
  updated_ca_json="$updated_ca_json" updated_defaults_json="$updated_defaults_json" \
    yq -i '
      .data."ca.json" = strenv(updated_ca_json) |
      .data."defaults.json" = strenv(updated_defaults_json)
    ' "$CONFIG_CM"

  echo "  resources-prod/step-cert-issuer.yaml ..."
  ca_bundle="$ca_bundle" \
    yq -i '.spec.acme.caBundle = strenv(ca_bundle)' "$ISSUER_YAML"

  # ── Print Bitwarden entries ────────────────────────────────────────────────

  cat <<EOF


╔══════════════════════════════════════════════════════════════════╗
║                 BITWARDEN — REQUIRED MANUAL UPDATES              ║
╚══════════════════════════════════════════════════════════════════╝

Update the following vault items. The UUIDs are the existing
items — update them in-place (do not create new ones).

────────────────────────────────────────────────────────────────────
  Item name : step-certificates-ca-password
  Field     : password
  Value     :
$CA_PASSWORD

────────────────────────────────────────────────────────────────────
  Item name : step-certificates-provisioner-password
  Field     : password
  Value     :
$PROV_PASSWORD

────────────────────────────────────────────────────────────────────
  Item name : step-certificates-secrets  (intermediate CA private key)
  Field     : intermediate_ca_key  (notes / custom field)
  Value     :
$intermediate_key

══════════════════════════════════════════════════════════════════

OFFLINE BACKUP — do NOT sync into cluster:

────────────────────────────────────────────────────────────────────
  Item name : step-certificates-secrets  (root CA private key)
  Field     : root_ca_key  (notes / custom field)
  Value     :
$root_key

══════════════════════════════════════════════════════════════════

Next steps:
  1. Update the 3 deployed Bitwarden items above (passwords + intermediate key)
  2. Store root CA key in Bitwarden as offline DR backup only
  3. Review:  git diff
  4. Commit and push to trigger ArgoCD sync
  5. step-ca pod will restart with the new PKI
  6. Force cert-manager renewal if needed:
       kubectl delete certificaterequest -A --all

EOF
}

main "$@"

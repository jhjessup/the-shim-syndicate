#!/usr/bin/env bash
# =============================================================================
# validate-shims.sh — Shim Configuration Validator
# =============================================================================
# Version: 1.0.0
# Repository: jhjessup/the-shim-syndicate
#
# DESCRIPTION:
#   Validates Syndicate shim configuration files (shims/*.shim.json) against
#   shims/routing.schema.json. Designed to be called by the pre-commit hook
#   (CHECK-6) and CI.
#
#   Validation strategy, per file:
#     1. `jq empty`         — JSON parse check (hard requirement).
#     2. python3 jsonschema — full schema validation, if the module is present.
#     3. jq fallback        — structural checks (required top-level keys,
#                             agents lead/ledger/gavel, per-agent
#                             primary_backend + identity_file) when the
#                             python3 jsonschema module is unavailable.
#
# USAGE:
#   bash scripts/validate-shims.sh                       # validate all shims/*.shim.json
#   bash scripts/validate-shims.sh shims/pi.shim.json    # validate specific file(s)
#   bash scripts/validate-shims.sh --schema /path/to/routing.schema.json [files...]
#
# EXIT CODES:
#   0 — All files passed validation.
#   1 — One or more files failed (or no shim files were found).
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

PASS="${GREEN}[PASS]${RESET}"
FAIL="${RED}[FAIL]${RESET}"
WARN="${YELLOW}[WARN]${RESET}"
INFO="${CYAN}[INFO]${RESET}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SCHEMA_PATH=""
FILES=()

# -----------------------------------------------------------------------------
# Argument parsing
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --schema)
      [[ $# -ge 2 ]] || { echo -e "${FAIL} --schema requires a path argument." >&2; exit 1; }
      SCHEMA_PATH="$2"; shift 2 ;;
    --help|-h)
      grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,2\}//' | sed 's/^#//'
      exit 0 ;;
    *)
      FILES+=("$1"); shift ;;
  esac
done

# Default file set: every *.shim.json next to the schema
if [[ ${#FILES[@]} -eq 0 ]]; then
  while IFS= read -r f; do
    FILES+=("$f")
  done < <(find "$REPO_ROOT/shims" -maxdepth 1 -name '*.shim.json' 2>/dev/null | sort)
fi

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo -e "${FAIL} No shim files found to validate." >&2
  exit 1
fi

# Default schema: next to the shims
if [[ -z "$SCHEMA_PATH" ]]; then
  SCHEMA_PATH="$REPO_ROOT/shims/routing.schema.json"
fi

if [[ ! -f "$SCHEMA_PATH" ]]; then
  echo -e "${FAIL} Schema not found: $SCHEMA_PATH" >&2
  exit 1
fi

# Pick validation backend
HAVE_JSONSCHEMA=false
if python3 -c "import jsonschema" &>/dev/null; then
  HAVE_JSONSCHEMA=true
  echo -e "${INFO} Validator: python3 jsonschema (full schema validation)"
else
  echo -e "${WARN} python3 jsonschema module unavailable — falling back to jq structural checks."
fi
echo -e "${INFO} Schema   : $SCHEMA_PATH"

# -----------------------------------------------------------------------------
# Validators
# -----------------------------------------------------------------------------
validate_full() {
  # $1 = shim file. Returns 0 on valid, 1 on invalid (error printed to stderr).
  python3 - "$SCHEMA_PATH" "$1" <<'PYEOF'
import json, sys
import jsonschema

schema_path, shim_path = sys.argv[1], sys.argv[2]
with open(schema_path) as fh:
    schema = json.load(fh)
with open(shim_path) as fh:
    instance = json.load(fh)
try:
    jsonschema.validate(instance=instance, schema=schema)
except jsonschema.ValidationError as exc:
    loc = "/".join(str(p) for p in exc.absolute_path) or "<root>"
    print(f"  at {loc}: {exc.message}", file=sys.stderr)
    sys.exit(1)
PYEOF
}

validate_structural() {
  # $1 = shim file. jq-only structural checks.
  jq -e '
    (has("syndicate_version") and has("routing_mode") and has("agents"))
    and (.agents | has("lead") and has("ledger") and has("gavel"))
    and ([.agents[] | has("primary_backend") and has("identity_file")] | all)
  ' "$1" > /dev/null
}

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------
FAIL_COUNT=0

for file in "${FILES[@]}"; do
  name="${file#"$REPO_ROOT"/}"

  if [[ ! -f "$file" ]]; then
    echo -e "${FAIL} $name — file not found"
    (( FAIL_COUNT++ )) || true
    continue
  fi

  # 1. JSON parse check
  if ! jq empty "$file" 2>/dev/null; then
    echo -e "${FAIL} $name — invalid JSON (jq parse failed)"
    (( FAIL_COUNT++ )) || true
    continue
  fi

  # 2/3. Schema or structural validation
  if [[ "$HAVE_JSONSCHEMA" == true ]]; then
    if validate_full "$file"; then
      echo -e "${PASS} $name — valid against $(basename "$SCHEMA_PATH")"
    else
      echo -e "${FAIL} $name — schema validation failed (see message above)"
      (( FAIL_COUNT++ )) || true
    fi
  else
    if validate_structural "$file"; then
      echo -e "${PASS} $name — structural checks passed (jq fallback)"
    else
      echo -e "${FAIL} $name — structural checks failed (missing required keys/agents)"
      (( FAIL_COUNT++ )) || true
    fi
  fi
done

echo ""
if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo -e "${FAIL} $FAIL_COUNT shim file(s) failed validation."
  exit 1
fi
echo -e "${PASS} All ${#FILES[@]} shim file(s) passed validation."
exit 0

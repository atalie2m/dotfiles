#!/usr/bin/env bash
set -euo pipefail

DOTFILES_SCRIPT_LABEL="doctor"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=load-lib.sh
source "$SCRIPT_DIR/load-lib.sh"

usage() {
  cat <<'USAGE'
Usage: nix run .#doctor -- [--host <host>] [--rice <rice>] [--strict] [--json]

Environment:
  HOST=...        Host to inspect (default: none)
  RICE=...        Rice to inspect (default: none)
  FACTS=...       Full local facts input (default: path:$HOME/.config/dotfiles)
  SECRETS=...     Full local secrets input (default: path:$HOME/.config/dotfiles)
  FACTS_DIR=...   Override local facts dir (default: $HOME/.config/dotfiles)
  SECRETS_DIR=... Override local secrets dir (default: $HOME/.config/dotfiles)
USAGE
}

host=""
rice=""
strict=0
json=0

while [[ $# -gt 0 ]]; do
  case "$1" in
  -h | --help)
    usage
    exit 0
    ;;
  --host)
    [[ $# -lt 2 ]] && die "missing value for --host"
    host="$2"
    shift 2
    ;;
  --rice)
    [[ $# -lt 2 ]] && die "missing value for --rice"
    rice="$2"
    shift 2
    ;;
  --strict)
    strict=1
    shift
    ;;
  --json)
    json=1
    shift
    ;;
  --)
    die "unexpected -- (no passthrough supported)"
    ;;
  --*)
    die "unknown option: $1"
    ;;
  *)
    die "unexpected argument: $1"
    ;;
  esac
done

host="${host:-${HOST:-}}"
rice="${rice:-${RICE:-}}"

set_repo_root
cd "$ROOT"
resolve_inputs

CHECK_NAMES=()
CHECK_STATUS=()
CHECK_MESSAGE=()
FAILURES=0
WARNINGS=0

record_check() {
  local name="$1"
  local status="$2"
  local message="$3"

  CHECK_NAMES+=("$name")
  CHECK_STATUS+=("$status")
  CHECK_MESSAGE+=("$message")

  case "$status" in
  fail) FAILURES=$((FAILURES + 1)) ;;
  warn) WARNINGS=$((WARNINGS + 1)) ;;
  esac

  if [[ $json -eq 0 ]]; then
    printf '%-5s %s: %s\n' "$status" "$name" "$message"
  fi
}

facts_file="$FACTS_DIR/facts.nix"
if [[ -f $facts_file ]]; then
  record_check "facts.exists" "ok" "$facts_file"
  if command -v nix >/dev/null 2>&1; then
    if schema_checks=$(nix eval --raw --file "$facts_file" --apply '
x:
let
  optionalString = value: value == null || builtins.isString value;
  optionalInt = value: value == null || builtins.isInt value;
  optionalAttrs = value: value == null || builtins.isAttrs value;
  optionalListOfStrings = value: value == null || (builtins.isList value && builtins.all builtins.isString value);

  hasRoot = builtins.isAttrs x;
  user = if hasRoot && builtins.hasAttr "user" x then x.user else null;
  hasUser = builtins.isAttrs user;

  username = if hasUser && builtins.hasAttr "username" user then user.username else null;
  usernameIsString = builtins.isString username;
  usernameNonEmpty = usernameIsString && username != "";

  fullName = if hasUser && builtins.hasAttr "fullName" user then user.fullName else null;
  email = if hasUser && builtins.hasAttr "email" user then user.email else null;
  homeDirectory = if hasUser && builtins.hasAttr "homeDirectory" user then user.homeDirectory else null;
  homeDirLooksAbsolute = builtins.isString homeDirectory && builtins.match "^/.+" homeDirectory != null;
  platform = if hasUser && builtins.hasAttr "platform" user then user.platform else null;

  stateVersion = if hasUser && builtins.hasAttr "stateVersion" user then user.stateVersion else null;
  stateHome = if builtins.isAttrs stateVersion && builtins.hasAttr "home" stateVersion then stateVersion.home else null;
  stateDarwin = if builtins.isAttrs stateVersion && builtins.hasAttr "darwin" stateVersion then stateVersion.darwin else null;

  machines = if hasRoot && builtins.hasAttr "machines" x then x.machines else null;
  binaryCaches = if hasRoot && builtins.hasAttr "binaryCaches" x then x.binaryCaches else null;
  substituters =
    if builtins.isAttrs binaryCaches && builtins.hasAttr "substituters" binaryCaches
    then binaryCaches.substituters
    else null;
  trustedPublicKeys =
    if builtins.isAttrs binaryCaches && builtins.hasAttr "trustedPublicKeys" binaryCaches
    then binaryCaches.trustedPublicKeys
    else null;

  mk = name: status: message: "${name}|${status}|${message}";
in
builtins.concatStringsSep "\n" [
  (mk "facts.schema.root" (if hasRoot then "ok" else "fail")
    (if hasRoot then "facts is an attrset" else "facts.nix must return an attrset"))
  (mk "facts.schema.user" (if hasUser then "ok" else "fail")
    (if hasUser then "facts.user is an attrset" else "facts.user must be an attrset"))
  (mk "facts.username" (if usernameNonEmpty then "ok" else "fail")
    (if usernameNonEmpty then username else "facts.user.username must be a non-empty string"))
  (mk "facts.fullName" (if optionalString fullName then "ok" else "fail")
    (if fullName == null then "facts.user.fullName not set (optional)"
     else if builtins.isString fullName then "facts.user.fullName set"
     else "facts.user.fullName must be a string"))
  (mk "facts.email" (if optionalString email then "ok" else "fail")
    (if email == null then "facts.user.email not set (optional)"
     else if builtins.isString email then "facts.user.email set"
     else "facts.user.email must be a string"))
  (mk "facts.homeDirectory" (if optionalString homeDirectory then "ok" else "fail")
    (if homeDirectory == null then "facts.user.homeDirectory not set (auto-derived)"
     else if builtins.isString homeDirectory then homeDirectory
     else "facts.user.homeDirectory must be a string"))
  (mk "facts.homeDirectoryFormat"
    (if homeDirectory == null then "ok"
     else if !builtins.isString homeDirectory then "fail"
     else if homeDirLooksAbsolute then "ok" else "warn")
    (if homeDirectory == null then "facts.user.homeDirectory not set (auto-derived)"
     else if !builtins.isString homeDirectory then "facts.user.homeDirectory must be a string"
     else if homeDirLooksAbsolute then "facts.user.homeDirectory is absolute"
     else "facts.user.homeDirectory should be an absolute path"))
  (mk "facts.platform" (if optionalString platform then "ok" else "fail")
    (if platform == null then "facts.user.platform not set (defaults to aarch64-darwin)"
     else if builtins.isString platform then platform
     else "facts.user.platform must be a string"))
  (mk "facts.stateVersion" (if optionalAttrs stateVersion then "ok" else "fail")
    (if stateVersion == null then "facts.user.stateVersion not set (optional)"
     else if builtins.isAttrs stateVersion then "facts.user.stateVersion set"
     else "facts.user.stateVersion must be an attrset"))
  (mk "facts.stateVersion.home" (if optionalString stateHome then "ok" else "fail")
    (if stateHome == null then "facts.user.stateVersion.home not set (optional)"
     else if builtins.isString stateHome then stateHome
     else "facts.user.stateVersion.home must be a string"))
  (mk "facts.stateVersion.darwin" (if optionalInt stateDarwin then "ok" else "fail")
    (if stateDarwin == null then "facts.user.stateVersion.darwin not set (optional)"
     else if builtins.isInt stateDarwin then builtins.toString stateDarwin
     else "facts.user.stateVersion.darwin must be an integer"))
  (mk "facts.machines" (if optionalAttrs machines then "ok" else "fail")
    (if machines == null then "facts.machines not set (optional)"
     else if builtins.isAttrs machines then "facts.machines set"
     else "facts.machines must be an attrset"))
  (mk "facts.binaryCaches" (if optionalAttrs binaryCaches then "ok" else "fail")
    (if binaryCaches == null then "facts.binaryCaches not set (optional)"
     else if builtins.isAttrs binaryCaches then "facts.binaryCaches set"
     else "facts.binaryCaches must be an attrset"))
  (mk "facts.binaryCaches.substituters" (if optionalListOfStrings substituters then "ok" else "fail")
    (if substituters == null then "facts.binaryCaches.substituters not set (optional)"
     else if builtins.isList substituters then "facts.binaryCaches.substituters set"
     else "facts.binaryCaches.substituters must be a list of strings"))
  (mk "facts.binaryCaches.trustedPublicKeys" (if optionalListOfStrings trustedPublicKeys then "ok" else "fail")
    (if trustedPublicKeys == null then "facts.binaryCaches.trustedPublicKeys not set (optional)"
     else if builtins.isList trustedPublicKeys then "facts.binaryCaches.trustedPublicKeys set"
     else "facts.binaryCaches.trustedPublicKeys must be a list of strings"))
]
' 2>/dev/null); then
      while IFS='|' read -r name status message; do
        [[ -z $name ]] && continue
        case "$status" in
        ok | warn | fail) ;;
        *)
          name="facts.schema"
          status="fail"
          message="invalid status returned by facts schema evaluator"
          ;;
        esac
        record_check "$name" "$status" "$message"
      done <<<"$schema_checks"
    else
      record_check "facts.eval" "fail" "unable to evaluate facts schema"
    fi
  else
    record_check "facts.eval" "fail" "nix not found (cannot evaluate facts)"
  fi
else
  record_check "facts.exists" "fail" "$facts_file missing"
fi

if [[ -f "$FACTS_DIR/STUB" ]]; then
  record_check "facts.stub" "fail" "STUB present in $FACTS_DIR (flake outputs are gated)"
else
  record_check "facts.stub" "ok" "no STUB in $FACTS_DIR"
fi

secrets_file="$SECRETS_DIR/secrets.nix"
if [[ -f $secrets_file ]]; then
  record_check "secrets.exists" "ok" "$secrets_file"
else
  record_check "secrets.exists" "fail" "$secrets_file missing"
fi

age_key_file="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"
if [[ -f $age_key_file ]]; then
  record_check "sops.ageKey" "ok" "$age_key_file"
else
  record_check "sops.ageKey" "warn" "$age_key_file missing"
fi

if command -v xcode-select >/dev/null 2>&1; then
  if xcode_path=$(xcode-select -p 2>/dev/null); then
    record_check "darwin.xcodeSelect" "ok" "$xcode_path"
  else
    record_check "darwin.xcodeSelect" "fail" "Command Line Tools not configured"
  fi
else
  record_check "darwin.xcodeSelect" "fail" "xcode-select not found"
fi

machine_arch=$(uname -m 2>/dev/null || true)
if [[ $machine_arch == "arm64" ]]; then
  if command -v arch >/dev/null 2>&1 && arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
    record_check "darwin.rosetta" "ok" "Rosetta available"
  else
    record_check "darwin.rosetta" "warn" "Rosetta not available"
  fi
else
  record_check "darwin.rosetta" "ok" "Not required on $machine_arch"
fi

if command -v nix >/dev/null 2>&1; then
  if targets=$(list_darwin_targets "$ROOT" "$FACTS" "$SECRETS"); then
    if [[ -z $targets ]]; then
      record_check "flake.targets" "fail" "no darwinConfigurations found"
    elif [[ -n $host ]]; then
      if [[ $json -eq 1 ]]; then
        target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS" 2>/dev/null || true)
      else
        target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS" || true)
      fi
      if [[ -n $target ]]; then
        if nix eval --raw "$ROOT#darwinConfigurations.${target}.system.drvPath" \
          --override-input local "$FACTS" \
          --override-input secrets "$SECRETS" \
          >/dev/null 2>&1; then
          record_check "flake.target" "ok" "$target"
        else
          record_check "flake.target" "fail" "unable to evaluate darwinConfigurations.${target}.system"
        fi
      else
        record_check "flake.target" "fail" "target resolution failed"
      fi
    else
      target_count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
      record_check "flake.targets" "ok" "darwinConfigurations available ($target_count targets)"
    fi
  else
    record_check "flake.targets" "fail" "unable to evaluate darwinConfigurations"
  fi
else
  record_check "flake.targets" "fail" "nix not found (cannot evaluate flake)"
fi

if [[ $strict -eq 1 ]]; then
  if nix flake check \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS" \
    >/dev/null 2>&1; then
    record_check "flake.check" "ok" "nix flake check passed"
  else
    record_check "flake.check" "fail" "nix flake check failed"
  fi

  if [[ $(uname -s 2>/dev/null || true) == "Darwin" ]]; then
    terminal_script="$SCRIPT_DIR/terminal.sh"
    if [[ -x $terminal_script ]]; then
      if "$terminal_script" sync --check >/dev/null 2>&1; then
        record_check "terminal.sync" "ok" "terminal sync check passed"
      else
        record_check "terminal.sync" "fail" "terminal sync check failed (run: nix run .#dotfiles -- terminal sync --check)"
      fi
    else
      record_check "terminal.sync" "warn" "terminal sync script not found; skipped"
    fi
  else
    record_check "terminal.sync" "ok" "skipped on non-Darwin host"
  fi
fi

if [[ $json -eq 1 ]]; then
  ok="false"
  if [[ $FAILURES -eq 0 ]]; then
    ok="true"
  fi
  printf '{'
  printf '"ok":%s,' "$ok"
  printf '"failures":%s,' "$FAILURES"
  printf '"warnings":%s,' "$WARNINGS"
  printf '"checks":['
  for i in "${!CHECK_NAMES[@]}"; do
    name=$(json_escape "${CHECK_NAMES[$i]}")
    status=$(json_escape "${CHECK_STATUS[$i]}")
    message=$(json_escape "${CHECK_MESSAGE[$i]}")
    printf '{"name":"%s","status":"%s","message":"%s"}' "$name" "$status" "$message"
    if [[ $i -lt $((${#CHECK_NAMES[@]} - 1)) ]]; then
      printf ','
    fi
  done
  printf ']}\n'
fi

if [[ $FAILURES -eq 0 ]]; then
  exit 0
fi
exit 1

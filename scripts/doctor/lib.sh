#!/usr/bin/env bash

# shellcheck disable=SC2120,SC2154

eval_darwin_target_bool() {
  local target_name="$1"
  local option_path="$2"

  nix eval --raw "${flake_ref}#darwinConfigurations.${target_name}.config.${option_path}" \
    --no-update-lock-file \
    --apply 'x: if x then "true" else "false"' \
    --override-input local "$FACTS" \
    --override-input secrets "$SECRETS" \
    2>/dev/null || true
}

record_facts_checks() {
  local facts_file schema_file schema_checks name status message

  facts_file="$FACTS_DIR/facts.nix"
  schema_file="$ROOT/nix/scripts/doctor/facts-schema.nix"

  if [[ -f $facts_file ]]; then
    record_check "facts.exists" "ok" "$facts_file"
    if command -v nix >/dev/null 2>&1; then
      if schema_checks=$(nix eval --raw --impure --expr "import ${schema_file} { factsFile = \"${facts_file}\"; }" 2>/dev/null); then
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
}

record_basic_system_checks() {
  local secrets_file age_key_file xcode_path machine_arch system_name

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

  system_name="$(uname -s 2>/dev/null || true)"
  if [[ $system_name != "Darwin" ]]; then
    record_check "darwin.xcodeSelect" "ok" "skipped on non-Darwin host"
    record_check "darwin.rosetta" "ok" "skipped on non-Darwin host"
    return 0
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
}

record_target_checks() {
  local targets target target_count

  if ! command -v nix >/dev/null 2>&1; then
    record_check "flake.targets" "fail" "nix not found (cannot evaluate flake)"
    return 0
  fi

  if ! targets=$(list_darwin_targets "$ROOT" "$FACTS" "$SECRETS"); then
    record_check "flake.targets" "fail" "unable to evaluate darwinConfigurations"
    return 0
  fi

  if [[ -z $targets ]]; then
    record_check "flake.targets" "fail" "no darwinConfigurations found"
    return 0
  fi

  if [[ -n $host ]]; then
    if [[ $json -eq 1 ]]; then
      target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS" 2>/dev/null || true)
    else
      target=$(resolve_target "$host" "$rice" "$ROOT" "$FACTS" "$SECRETS" || true)
    fi

    if [[ -z $target ]]; then
      record_check "flake.target" "fail" "target resolution failed"
      return 0
    fi

    resolved_target="$target"
    if nix eval --raw "${flake_ref}#darwinConfigurations.${target}.system.drvPath" \
      --no-update-lock-file \
      --override-input local "$FACTS" \
      --override-input secrets "$SECRETS" \
      >/dev/null 2>&1; then
      record_check "flake.target" "ok" "$target"
    else
      record_check "flake.target" "fail" "unable to evaluate darwinConfigurations.${target}.system"
    fi
    return 0
  fi

  target_count=$(printf '%s\n' "$targets" | awk 'NF{c++} END{print c+0}')
  record_check "flake.targets" "ok" "darwinConfigurations available ($target_count targets)"
}

record_strict_sync_checks() {
  local sync_script shell_enabled shell_output shell_summary
  local shell_zsh_enabled="" shell_bash_enabled="" shell_check_args shell_enabled_count
  local root_compat_enabled="" root_compat_output root_compat_summary compat_script
  local vscode_enabled="" vscode_sync_enabled="" vscode_output="" vscode_summary=""

  sync_script="$SCRIPT_DIR/sync.sh"
  compat_script="$SCRIPT_DIR/zshrc-compat.sh"
  if [[ -z $resolved_target ]]; then
    record_check "shell.sync" "warn" "strict sync check skipped (pass --host to resolve target)"
    record_check "shell.zsh.rootCompat" "warn" "strict root compat check skipped (pass --host to resolve target)"
    record_check "vscode.sync" "warn" "strict VS Code sync check skipped (pass --host to resolve target)"
    return 0
  fi

  shell_zsh_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.shell.zsh.enable")"
  shell_bash_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.shell.bash.enable")"

  shell_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.shell.sync.enable")"
  if [[ -z $shell_enabled ]]; then
    shell_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.shell.enable")"
  fi
  vscode_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.editor.vscode.enable")"
  vscode_sync_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.editor.vscode.sync.enable")"

  case "$shell_enabled" in
  true)
    if [[ -f $sync_script ]]; then
      shell_check_args=(shell --check --details)
      shell_enabled_count=0
      if [[ $shell_zsh_enabled == "true" ]]; then
        shell_check_args+=(--group zsh)
        shell_enabled_count=$((shell_enabled_count + 1))
      fi
      if [[ $shell_bash_enabled == "true" ]]; then
        shell_check_args+=(--group bash)
        shell_enabled_count=$((shell_enabled_count + 1))
      fi

      if [[ $shell_enabled_count -eq 0 ]]; then
        record_check "shell.sync" "ok" "shell sync enabled but no shell targets are enabled; skipped"
      elif shell_output=$(bash "$sync_script" "${shell_check_args[@]}" 2>&1); then
        record_check "shell.sync" "ok" "shell sync check passed"
      else
        shell_summary="$(printf '%s\n' "$shell_output" | awk '/summary:/ { print; exit }')"
        if [[ -n $shell_summary ]]; then
          record_check "shell.sync" "fail" "shell sync check failed: $shell_summary (inspect: nix run .#dotfiles -- sync shell --check --details --diff)"
        else
          record_check "shell.sync" "fail" "shell sync check failed (inspect: nix run .#dotfiles -- sync shell --check --details --diff)"
        fi
      fi
    else
      record_check "shell.sync" "warn" "sync script not found; skipped"
    fi
    ;;
  false)
    record_check "shell.sync" "ok" "disabled in target $resolved_target; skipped"
    ;;
  *)
    record_check "shell.sync" "warn" "unable to resolve shell enablement for target $resolved_target; skipped"
    ;;
  esac

  case "$shell_zsh_enabled" in
  true)
    root_compat_enabled="$(eval_darwin_target_bool "$resolved_target" "myconfig.tools.shell.zsh.rootZshrcCompat.enable")"
    case "$root_compat_enabled" in
    true)
      if [[ -f $compat_script ]]; then
        if root_compat_output=$(bash "$compat_script" --check 2>&1); then
          record_check "shell.zsh.rootCompat" "ok" "zsh root compat check passed"
        else
          root_compat_summary="$(printf '%s\n' "$root_compat_output" | awk '/summary:/ { print; exit }')"
          if [[ -n $root_compat_summary ]]; then
            record_check "shell.zsh.rootCompat" "fail" "zsh root compat check failed: $root_compat_summary (inspect: bash scripts/zshrc-compat.sh --check)"
          else
            record_check "shell.zsh.rootCompat" "fail" "zsh root compat check failed (inspect: bash scripts/zshrc-compat.sh --check)"
          fi
        fi
      else
        record_check "shell.zsh.rootCompat" "warn" "zshrc compat script not found; skipped"
      fi
      ;;
    false)
      record_check "shell.zsh.rootCompat" "ok" "disabled in target $resolved_target"
      ;;
    *)
      record_check "shell.zsh.rootCompat" "warn" "unable to resolve zsh root compat enablement for target $resolved_target; skipped"
      ;;
    esac
    ;;
  false)
    record_check "shell.zsh.rootCompat" "ok" "zsh disabled in target $resolved_target; skipped"
    ;;
  *)
    record_check "shell.zsh.rootCompat" "warn" "unable to resolve zsh enablement for target $resolved_target; skipped"
    ;;
  esac

  case "$vscode_enabled" in
  true)
    case "$vscode_sync_enabled" in
    true)
      if [[ -f $sync_script ]]; then
        if vscode_output=$(bash "$sync_script" vscode --check --details 2>&1); then
          record_check "vscode.sync" "ok" "VS Code sync check passed"
        else
          vscode_summary="$(printf '%s\n' "$vscode_output" | awk '/summary:/ { print; exit }')"
          if [[ -n $vscode_summary ]]; then
            record_check "vscode.sync" "fail" "VS Code sync check failed: $vscode_summary (inspect: nix run .#dotfiles -- sync vscode --check --details --diff)"
          else
            record_check "vscode.sync" "fail" "VS Code sync check failed (inspect: nix run .#dotfiles -- sync vscode --check --details --diff)"
          fi
        fi
      else
        record_check "vscode.sync" "warn" "sync script not found; skipped"
      fi
      ;;
    false)
      record_check "vscode.sync" "ok" "sync disabled in target $resolved_target; skipped"
      ;;
    *)
      record_check "vscode.sync" "warn" "unable to resolve VS Code sync enablement for target $resolved_target; skipped"
      ;;
    esac
    ;;
  false)
    record_check "vscode.sync" "ok" "disabled in target $resolved_target; skipped"
    ;;
  *)
    record_check "vscode.sync" "warn" "unable to resolve VS Code enablement for target $resolved_target; skipped"
    ;;
  esac
}

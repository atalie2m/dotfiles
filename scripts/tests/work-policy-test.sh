#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$ROOT"
flake_ref="git+file://$ROOT"

if ! command -v nix >/dev/null 2>&1; then
  echo "FAIL: work policy test requires nix" >&2
  exit 1
fi

work_state="$(
  nix eval --raw --impure --expr '
    let
      flake = builtins.getFlake "'"$flake_ref"'";
      cfg = flake.darwinConfigurations.work_mac-ultra.config.myconfig.tools;
      bool = value: if value then "true" else "false";
    in
    builtins.concatStringsSep "\n" [
      "tools.editor.emacs.sync.enable=${bool cfg.editor.emacs.sync.enable}"
      "tools.editor.emacs.bootstrap.enable=${bool cfg.editor.emacs.bootstrap.enable}"
      "tools.editor.neovim.sync.enable=${bool cfg.editor.neovim.sync.enable}"
      "tools.editor.vscode.sync.enable=${bool cfg.editor.vscode.sync.enable}"
      "tools.aiCodingAgent.enable=${bool cfg.aiCodingAgent.enable}"
      "tools.aiCodingAgent.codex.enable=${bool cfg.aiCodingAgent.codex.enable}"
      "tools.aiCodingAgent.headroom.enable=${bool cfg.aiCodingAgent.headroom.enable}"
      "tools.aiCodingAgent.codex.slackNotifications.enable=${bool cfg.aiCodingAgent.codex.slackNotifications.enable}"
      "tools.aiLlm.enable=${bool cfg.aiLlm.enable}"
      "tools.aiLlm.aider.enable=${bool cfg.aiLlm.aider.enable}"
      "tools.modelHfPersonal.enable=${bool cfg.modelHfPersonal.enable}"
      "tools.backupRecovery.restic.enable=${bool cfg.backupRecovery.restic.enable}"
      "tools.terminalVisual.enable=${bool cfg.terminalVisual.enable}"
      "tools.terminalVisual.kitty.enable=${bool cfg.terminalVisual.kitty.enable}"
      "tools.system.latestApp.enable=${bool cfg.system.latestApp.enable}"
      "tools.downloadArchive.ffmpeg.enable=${bool cfg.downloadArchive.ffmpeg.enable}"
      "tools.passwordSecrets.op.enable=${bool cfg.passwordSecrets.op.enable}"
      "tools.dev.git.enable=${bool cfg.dev.git.enable}"
      "tools.editor.neovim.enable=${bool cfg.editor.neovim.enable}"
      "tools.containerK8sPersonal.kubectl.enable=${bool cfg.containerK8sPersonal.kubectl.enable}"
      "tools.system.hostnames.enable=${bool cfg.system.hostnames.enable}"
      "tools.downloadArchive.unzip.enable=${bool cfg.downloadArchive.unzip.enable}"
      "tools.passwordSecrets.age.enable=${bool cfg.passwordSecrets.age.enable}"
    ]
  '
)"

work_homebrew_casks="$(
  nix eval --raw --impure --expr '
    let
      flake = builtins.getFlake "'"$flake_ref"'";
      caskName = raw:
        if builtins.isAttrs raw then raw.name or ""
        else raw;
      casks = flake.darwinConfigurations.work_mac-ultra.config.homebrew.casks or [];
    in
    builtins.concatStringsSep "\n" (builtins.map caskName casks)
  '
)"

own_ultra_vscode_sync="$(
  nix eval --json "${flake_ref}#darwinConfigurations.own_mac-ultra.config.myconfig.tools.editor.vscode.sync.enable" --impure
)"

own_pro_codex_slack_notifications="$(
  nix eval --json "${flake_ref}#darwinConfigurations.own_mac.config.myconfig.tools.aiCodingAgent.codex.slackNotifications.enable" --impure
)"

own_ultra_codex_slack_notifications="$(
  nix eval --json "${flake_ref}#darwinConfigurations.own_mac-ultra.config.myconfig.tools.aiCodingAgent.codex.slackNotifications.enable" --impure
)"

own_pro_headroom="$(
  nix eval --json "${flake_ref}#darwinConfigurations.own_mac.config.myconfig.tools.aiCodingAgent.headroom.enable" --impure
)"

own_ultra_headroom="$(
  nix eval --json "${flake_ref}#darwinConfigurations.own_mac-ultra.config.myconfig.tools.aiCodingAgent.headroom.enable" --impure
)"

assert_toggle() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(
    printf '%s\n' "$work_state" |
      awk -F= -v key="$path" '$1 == key { print $2 }'
  )"

  if [[ $actual != "$expected" ]]; then
    echo "FAIL: work_mac-ultra.${path} expected ${expected}, got ${actual:-<missing>}" >&2
    exit 1
  fi
}

assert_line_absent() {
  local label="$1"
  local list="$2"
  local forbidden="$3"

  if printf '%s\n' "$list" | awk -v item="$forbidden" '$0 == item { found = 1 } END { exit found ? 0 : 1 }'; then
    echo "FAIL: ${label} unexpectedly contains ${forbidden}" >&2
    exit 1
  fi
}

for path in \
  tools.editor.emacs.sync.enable \
  tools.editor.emacs.bootstrap.enable \
  tools.editor.neovim.sync.enable \
  tools.editor.vscode.sync.enable \
  tools.aiCodingAgent.enable \
  tools.aiCodingAgent.codex.enable \
  tools.aiCodingAgent.headroom.enable \
  tools.aiCodingAgent.codex.slackNotifications.enable \
  tools.aiLlm.enable \
  tools.aiLlm.aider.enable \
  tools.modelHfPersonal.enable \
  tools.backupRecovery.restic.enable \
  tools.terminalVisual.enable \
  tools.terminalVisual.kitty.enable \
  tools.system.latestApp.enable \
  tools.downloadArchive.ffmpeg.enable \
  tools.passwordSecrets.op.enable; do
  assert_toggle "$path" false
done

for path in \
  tools.dev.git.enable \
  tools.editor.neovim.enable \
  tools.containerK8sPersonal.kubectl.enable \
  tools.system.hostnames.enable \
  tools.downloadArchive.unzip.enable \
  tools.passwordSecrets.age.enable; do
  assert_toggle "$path" true
done

for cask in \
  codex \
  claude-code@latest \
  copilot-cli \
  keyclu \
  latest \
  nikitabobko/tap/aerospace \
  xcodes-app \
  font-anka-coder \
  kitty; do
  assert_line_absent "work_mac-ultra.homebrew.casks" "$work_homebrew_casks" "$cask"
done

if [[ $own_ultra_vscode_sync != "true" ]]; then
  echo "FAIL: own_mac-ultra.tools.editor.vscode.sync.enable expected true, got $own_ultra_vscode_sync" >&2
  exit 1
fi

if [[ $own_pro_codex_slack_notifications != "false" ]]; then
  echo "FAIL: own_mac.tools.aiCodingAgent.codex.slackNotifications.enable expected false, got $own_pro_codex_slack_notifications" >&2
  exit 1
fi

if [[ $own_ultra_codex_slack_notifications != "true" ]]; then
  echo "FAIL: own_mac-ultra.tools.aiCodingAgent.codex.slackNotifications.enable expected true, got $own_ultra_codex_slack_notifications" >&2
  exit 1
fi

if [[ $own_pro_headroom != "false" ]]; then
  echo "FAIL: own_mac.tools.aiCodingAgent.headroom.enable expected false, got $own_pro_headroom" >&2
  exit 1
fi

if [[ $own_ultra_headroom != "true" ]]; then
  echo "FAIL: own_mac-ultra.tools.aiCodingAgent.headroom.enable expected true, got $own_ultra_headroom" >&2
  exit 1
fi

echo "PASS: work policy"

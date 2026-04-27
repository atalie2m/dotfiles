{ dotmod, config, lib, dotlib, pkgs, repoPaths, ... }:

# VS Code sync tooling plus native profile reconciliation.

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.vscode";
  dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
  syncVscodeBin = pkgs.callPackage ../../../pkgs/dotfiles-sync-vscode { };
  types = lib.types;
in
(dotmod.mkModule { inherit config; }) {
  path = "tools.editor.vscode";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    sync = {
      enable = boolOption false;
      managedDir = lib.mkOption {
        type = types.nullOr types.path;
        default = null;
      };
      stateDir = lib.mkOption {
        type = types.nullOr types.str;
        default = null;
      };
    };
  };

  homeOnEnable = { ... }: {
    home.packages = [ syncVscodeBin ];
  };

  myconfigOnEnable = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  darwinOnEnable = { cfg, ... }:
    let
      runtimePath = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gawk
        pkgs.gnugrep
        syncVscodeBin
      ];
      stateDirExpr =
        if cfg.sync.stateDir != null
        then lib.escapeShellArg cfg.sync.stateDir
        else "\"\${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode\"";
      managedDirArg =
        if cfg.sync.managedDir != null
        then toString cfg.sync.managedDir
        else "${repoPaths.apps}/vscode";
      applyArgs =
        [
          "${dotfilesCli}/bin/dotfiles"
          "sync"
          "vscode"
          "--managed-dir"
          managedDirArg
          "--apply"
        ];
    in
    {
      home-manager.sharedModules = lib.optional cfg.sync.enable ({ ... }: {
        home.activation.syncVscodeProfiles = lib.mkOrder 900 ''
          export PATH="${runtimePath}:$PATH"
          export DOTFILES_SYNC_VSCODE_BIN="${syncVscodeBin}/bin/dotfiles-sync-vscode"
          if [[ -n "''${VSCODE_CODE_BIN:-}" && ! -x "''${VSCODE_CODE_BIN}" ]]; then
            echo "vscode sync: configured VSCODE_CODE_BIN is not executable, skipping activation sync" >&2
          else
            if [[ -z "''${VSCODE_CODE_BIN:-}" ]]; then
              if command -v code >/dev/null 2>&1; then
                export VSCODE_CODE_BIN="$(command -v code)"
              elif [[ -x "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
                export VSCODE_CODE_BIN="$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
              elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
                export VSCODE_CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
              fi
            fi
            if [[ -z "''${VSCODE_CODE_BIN:-}" ]]; then
              echo "vscode sync: Visual Studio Code.app not found, skipping activation sync" >&2
            else
              state_dir=${stateDirExpr}
              ${lib.escapeShellArgs applyArgs} --state-dir "$state_dir"
            fi
          fi
        '';
      });
    };
}

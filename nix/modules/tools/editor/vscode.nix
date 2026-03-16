{ delib, lib, pkgs, repoPaths, ... }:

# VS Code package wiring plus native profile reconciliation.

let
  syncVscodeBin = pkgs.callPackage ../../../pkgs/dotfiles-sync-vscode { };
  types = lib.types;
in
delib.module {
  name = "tools.editor.vscode";

  options = with delib; args:
    (moduleOptions
      {
        enable = boolOption false;
        sync = {
          enable = boolOption true;
          managedDir = lib.mkOption {
            type = types.nullOr types.path;
            default = null;
          };
          stateDir = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
        };
      }
      args)
  ;

  home.ifEnabled = { ... }: {
    home.packages = [ syncVscodeBin ];
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      syncScript = "${repoPaths.scripts}/sync.sh";
      runtimePath = lib.makeBinPath [
        pkgs.bash
        pkgs.coreutils
        pkgs.diffutils
        pkgs.gawk
        pkgs.gnugrep
        pkgs.sqlite
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
          "bash"
          syncScript
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
          if [[ -z "''${VSCODE_CODE_BIN:-}" ]]; then
            if [[ -x "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
              export VSCODE_CODE_BIN="$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            elif [[ -x "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" ]]; then
              export VSCODE_CODE_BIN="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
            fi
          fi
          state_dir=${stateDirExpr}
          ${lib.escapeShellArgs applyArgs} --state-dir "$state_dir"
        '';
      });
    };
}

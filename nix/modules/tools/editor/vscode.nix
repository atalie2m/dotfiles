{ delib, lib, dotlib, pkgs, repoPaths, ... }:

# VS Code package wiring plus native profile reconciliation.

delib.module {
  name = "tools.editor.vscode";

  options = with delib; moduleOptions {
    enable = boolOption false;
    managedDir = strOption "";
    stateDir = strOption "";
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.editor.vscode.enable";
    ifEnabled = { ... }: dotlib.requireUnfree [ "vscode" ];
  };

  home.ifEnabled = { ... }: {
    home.packages = [ pkgs.vscode ];
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
        pkgs.jq
        pkgs.vscode
      ];
      stateDirExpr =
        if cfg.stateDir != ""
        then lib.escapeShellArg cfg.stateDir
        else "\"\${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode\"";
      managedDirArg =
        if cfg.managedDir != ""
        then cfg.managedDir
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
      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.syncVscodeProfiles = lib.mkOrder 900 ''
            export PATH="${runtimePath}:$PATH"
            state_dir=${stateDirExpr}
            ${lib.escapeShellArgs applyArgs} --state-dir "$state_dir"
          '';
        })
      ];
    };
}

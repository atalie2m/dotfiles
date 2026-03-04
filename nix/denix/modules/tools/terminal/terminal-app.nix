{ delib, lib, dotlib, inputs, ... }:

# macOS Terminal.app profile reconciliation via nix/scripts/terminal.sh.

delib.module {
  name = "tools.terminal.terminalApp";

  options = with delib; moduleOptions {
    enable = boolOption false;
    managedDir = strOption "${inputs.self}/apps/terminal";
    defaultProfile = strOption "";
    startupProfile = strOption "";
    forceImport = boolOption false;
    failOnDrift = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.terminal.terminalApp.enable";
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      terminalSyncScript = "${inputs.self}/nix/scripts/terminal.sh";
      applyArgs =
        [ terminalSyncScript "sync" "--apply" "--dir" cfg.managedDir ]
        ++ lib.optional cfg.forceImport "--force"
        ++ lib.optionals (cfg.defaultProfile != "") [ "--default-profile" cfg.defaultProfile ]
        ++ lib.optionals (cfg.startupProfile != "") [ "--startup-profile" cfg.startupProfile ];
      checkArgs = [ terminalSyncScript "sync" "--check" "--details" "--dir" cfg.managedDir ];
    in
    {
      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.configureTerminalProfiles = lib.mkOrder 600 ''
            if [ "${lib.boolToString cfg.failOnDrift}" = "true" ]; then
              ${lib.escapeShellArgs applyArgs}
            else
              ${lib.escapeShellArgs checkArgs} || true
            fi
          '';
        })
      ];
    };
}

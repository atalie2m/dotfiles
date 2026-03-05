{ delib, lib, dotlib, inputs, ... }:

# macOS Terminal.app profile reconciliation via nix/scripts/sync.sh.

delib.module {
  name = "tools.terminal.terminalApp";

  options = with delib; moduleOptions {
    enable = boolOption false;
    managedDir = strOption "${inputs.self}/surfaces/terminal/desired";
    stateDir = strOption "";
    force = boolOption false;
    extraArgs = listOfOption str [ ];
    defaultProfile = strOption "";
    startupProfile = strOption "";
    failOnDrift = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.terminal.terminalApp.enable";
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      syncScript = "${inputs.self}/nix/scripts/sync.sh";
      commonArgs =
        [ "bash" syncScript "terminal" "--profiles-dir" cfg.managedDir ]
        ++ lib.optionals (cfg.stateDir != "") [ "--state-dir" cfg.stateDir ]
        ++ cfg.extraArgs;
      applyArgs =
        commonArgs
        ++ [ "--apply" ]
        ++ lib.optional cfg.force "--force"
        ++ lib.optionals (cfg.defaultProfile != "") [ "--default-profile" cfg.defaultProfile ]
        ++ lib.optionals (cfg.startupProfile != "") [ "--startup-profile" cfg.startupProfile ];
      checkArgs = commonArgs ++ [ "--check" "--details" ];
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

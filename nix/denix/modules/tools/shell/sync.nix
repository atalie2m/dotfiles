{ delib, lib, dotlib, inputs, ... }:

# Shell reconciliation via Home Manager activation.

delib.module {
  name = "tools.shell.sync";

  options = with delib; moduleOptions {
    enable = boolOption false;
    managedDir = strOption "${inputs.self}/surfaces/shell/desired";
    stateDir = strOption "";
    force = boolOption false;
    extraArgs = listOfOption str [ ];
    failOnDrift = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.sync.enable";
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      syncScript = "${inputs.self}/nix/scripts/sync.sh";
      shellCfg = ((myconfig.tools or { }).shell or { });
      zshEnabled = ((shellCfg.zsh or { }).enable or false);
      bashEnabled = ((shellCfg.bash or { }).enable or false);
      fishEnabled = ((shellCfg.fish or { }).enable or false);
      shellFilters = lib.concatLists [
        (lib.optionals zshEnabled [ "--group" "zsh" ])
        (lib.optionals bashEnabled [ "--group" "bash" ])
        (lib.optionals fishEnabled [ "--group" "fish" ])
      ];
      noSelectedShells = shellFilters == [ ];
      commonArgs =
        [ "bash" syncScript "shell" "--managed-dir" cfg.managedDir ]
        ++ lib.optionals (cfg.stateDir != "") [ "--state-dir" cfg.stateDir ]
        ++ shellFilters
        ++ cfg.extraArgs;
      applyArgs = commonArgs ++ [ "--apply" ] ++ lib.optional cfg.force "--force";
      checkArgs = commonArgs ++ [ "--check" "--details" ];
    in
    {
      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.syncShellManagedBlocks = lib.mkOrder 900 ''
            if [ "${lib.boolToString noSelectedShells}" = "true" ]; then
              echo "shell sync: no enabled shells selected, skipping" >&2
            elif [ "${lib.boolToString cfg.failOnDrift}" = "true" ]; then
              ${lib.escapeShellArgs applyArgs}
            else
              ${lib.escapeShellArgs checkArgs} || true
            fi
          '';
        })
      ];
    };
}

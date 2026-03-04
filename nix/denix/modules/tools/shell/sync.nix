{ delib, lib, dotlib, inputs, ... }:

# Shell reconciliation via Home Manager activation.

delib.module {
  name = "tools.shell.sync";

  options = with delib; moduleOptions {
    enable = boolOption false;
    forceApply = boolOption false;
    failOnDrift = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.sync.enable";
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      shellSyncScript = "${inputs.self}/nix/scripts/shell.sh";
    in
    {
      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.syncShellManagedBlocks = lib.mkOrder 900 ''
            if [ "${lib.boolToString cfg.failOnDrift}" = "true" ]; then
              ${lib.escapeShellArgs (
                [ shellSyncScript "sync" "--apply" ]
                ++ lib.optional cfg.forceApply "--force"
              )}
            else
              ${lib.escapeShellArgs [ shellSyncScript "sync" "--check" "--details" ]} || true
            fi
          '';
        })
      ];
    };
}

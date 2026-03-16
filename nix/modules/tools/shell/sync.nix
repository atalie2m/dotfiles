{ delib, lib, pkgs, repoPaths, ... }:

# Shell reconciliation via Home Manager activation.

delib.module {
  name = "tools.shell.sync";

  options = with delib; moduleOptions {
    enable = boolOption false;
    managedDir = strOption "${repoPaths.surfaces}/shell/desired";
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
      shellCfg = ((myconfig.tools or { }).shell or { });
      zshEnabled = ((shellCfg.zsh or { }).enable or false);
      bashEnabled = ((shellCfg.bash or { }).enable or false);
      shellFilters = lib.concatLists [
        (lib.optionals zshEnabled [ "--group" "zsh" ])
        (lib.optionals bashEnabled [ "--group" "bash" ])
      ];
      noSelectedShells = shellFilters == [ ];
      applyArgs =
        [ "${dotfilesCli}/bin/dotfiles" "sync" "shell" "--managed-dir" cfg.managedDir ]
        ++ shellFilters
        ++ [ "--apply" ];
    in
    {
      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.syncShellManagedBlocks = lib.mkOrder 900 ''
            if [ "${lib.boolToString noSelectedShells}" = "true" ]; then
              echo "shell sync: no enabled shells selected, skipping" >&2
            else
              ${lib.escapeShellArgs applyArgs}
            fi
          '';
        })
      ];
    };
}

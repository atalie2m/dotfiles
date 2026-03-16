{ delib, lib, inputs, pkgs, ... }:

# mac-app-util integration for Spotlight/Dock trampolines
# https://github.com/hraban/mac-app-util

delib.module {
  name = "tools.system.macAppUtil";

  options = with delib; moduleOptions {
    enable = boolOption false;
    systemService = {
      enable = boolOption false;
      timeoutSeconds = intOption 15;
    };
    homeTrampolines = {
      enable = boolOption true;
      syncDock = boolOption false;
      timeoutSeconds = intOption 15;
      fromDir = strOption "$HOME/Applications/Home Manager Apps";
      toDir = strOption "$HOME/Applications/Home Manager Trampolines";
    };
  };

  darwin.always = { ... }: {
    imports = [ inputs.mac-app-util.darwinModules.default ];
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      macAppUtil = inputs.mac-app-util.packages.${pkgs.stdenv.hostPlatform.system}.default;
      systemTimeoutCmd = "${pkgs.coreutils}/bin/timeout ${toString cfg.systemService.timeoutSeconds}s";
      homeTimeoutCmd = "${pkgs.coreutils}/bin/timeout ${toString cfg.homeTrampolines.timeoutSeconds}s";
      fromDir = cfg.homeTrampolines.fromDir;
      toDir = cfg.homeTrampolines.toDir;
    in
    {
      services.mac-app-util.enable = lib.mkDefault false;
      system.activationScripts.macAppUtilTrampolines = lib.mkIf cfg.systemService.enable {
        deps = [ "applications" ];
        text = ''
          fromDir="/Applications/Nix Apps"
          toDir="/Applications/Nix Trampolines"
          if [ -d "$fromDir" ]; then
            ${systemTimeoutCmd} ${macAppUtil}/bin/mac-app-util sync-trampolines "$fromDir" "$toDir" || true
          fi
        '';
      };
      home-manager.sharedModules = lib.optional cfg.homeTrampolines.enable (
        { ... }:
        {
          home.activation.macAppUtilTrampolines = lib.mkOrder 200 ''
            fromDir="${fromDir}"
            toDir="${toDir}"

            validateTrampolineDirs() {
              local homeApplicationsRoot
              homeApplicationsRoot="$HOME/Applications"

              if [ -z "$fromDir" ]; then
                echo "mac-app-util: fromDir is empty, skipping home trampolines" >&2
                return 1
              fi

              if [ -z "$toDir" ]; then
                echo "mac-app-util: toDir is empty, skipping home trampolines" >&2
                return 1
              fi

              if [ "$toDir" = "/" ]; then
                echo "mac-app-util: refusing to manage '/' as the trampoline destination" >&2
                return 1
              fi

              if [ "$fromDir" = "$toDir" ]; then
                echo "mac-app-util: refusing to use the same path for fromDir and toDir: $toDir" >&2
                return 1
              fi

              case "$toDir" in
                "$homeApplicationsRoot"|"$homeApplicationsRoot"/*) ;;
                *)
                  echo "mac-app-util: refusing to manage non-\$HOME/Applications destination: $toDir" >&2
                  return 1
                  ;;
              esac

              return 0
            }

            if [ -d "$fromDir" ]; then
              if validateTrampolineDirs; then
                if [ "${lib.boolToString cfg.homeTrampolines.syncDock}" = "true" ]; then
                  ${homeTimeoutCmd} ${macAppUtil}/bin/mac-app-util sync-trampolines "$fromDir" "$toDir" || true
                else
                  rm -rf "$toDir"
                  mkdir -p "$toDir"
                  while IFS= read -r -d $'\\0' app; do
                    dest="$toDir/$(basename "$app")"
                    ${macAppUtil}/bin/mac-app-util mktrampoline "$app" "$dest"
                  done < <(find "$fromDir" -maxdepth 2 -type d -name "*.app" -print0)
                fi
              fi
            fi
          '';
        }
      );
    };
}

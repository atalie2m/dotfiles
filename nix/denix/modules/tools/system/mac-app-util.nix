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

  myconfig = {
    always = { parent, ... }: {
      tools.system.macAppUtil.enable = lib.mkDefault parent.enable;
    };
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      macAppUtil = inputs.mac-app-util.packages.${pkgs.stdenv.system}.default;
      timeoutCmd = "${pkgs.coreutils}/bin/timeout ${toString cfg.systemService.timeoutSeconds}s";
    in
    {
      services.mac-app-util.enable = lib.mkForce false;
      system.activationScripts.macAppUtilTrampolines = lib.mkIf cfg.systemService.enable {
        deps = [ "applications" ];
        text = ''
          fromDir="/Applications/Nix Apps"
          toDir="/Applications/Nix Trampolines"
          if [ -d "$fromDir" ]; then
            ${timeoutCmd} ${macAppUtil}/bin/mac-app-util sync-trampolines "$fromDir" "$toDir" || true
          fi
        '';
      };
    };

  home.ifEnabled = { cfg, ... }:
    let
      macAppUtil = inputs.mac-app-util.packages.${pkgs.stdenv.system}.default;
      fromDir = cfg.homeTrampolines.fromDir;
      toDir = cfg.homeTrampolines.toDir;
      timeoutCmd = "${pkgs.coreutils}/bin/timeout ${toString cfg.homeTrampolines.timeoutSeconds}s";
    in
    lib.mkIf cfg.homeTrampolines.enable {
      home.activation.macAppUtilTrampolines = lib.mkOrder 200 ''
        fromDir="${fromDir}"
        toDir="${toDir}"

        if [ ! -d "$fromDir" ]; then
          exit 0
        fi

        if [ "${lib.boolToString cfg.homeTrampolines.syncDock}" = "true" ]; then
          ${timeoutCmd} ${macAppUtil}/bin/mac-app-util sync-trampolines "$fromDir" "$toDir" || true
        else
          rm -rf "$toDir"
          mkdir -p "$toDir"
          while IFS= read -r -d $'\\0' app; do
            dest="$toDir/$(basename "$app")"
            ${macAppUtil}/bin/mac-app-util mktrampoline "$app" "$dest"
          done < <(find "$fromDir" -maxdepth 2 -type d -name "*.app" -print0)
        fi
      '';
    };
}

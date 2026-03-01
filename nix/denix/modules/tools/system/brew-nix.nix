{ delib, lib, inputs, pkgs, ... }:

# Brew-nix integration for managing macOS applications via Nix.
# Kept as a secondary path for pinned/verified casks (empty by default).
delib.module {
  name = "tools.system.brewNix";

  options = with delib; moduleOptions {
    enable = boolOption false;
    autoDock.enable = boolOption false;
    autoTrampolines.enable = boolOption true;
    appLinks = {
      enable = boolOption false;
      targetDir = strOption "/Applications/Brew-nix Apps";
    };
    casks = attrsOption { };
    extraCasks = attrsOption { };
  };

  myconfig = {
    always = { parent, ... }: {
      tools.system.brewNix.enable = lib.mkDefault parent.enable;
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      caskApps = cfg.casks // cfg.extraCasks;
      caskNames = lib.attrNames caskApps;
      appLinkSpecs = map (cask: "${cask}|${caskApps.${cask}}") caskNames;
    in
    {
      # Enable brew-nix overlay
      nixpkgs.overlays = [ inputs.brew-nix.overlays.default ];

      # Enable brew-nix
      brew-nix.enable = true;

      # Keep Nix apps discoverable via Spotlight and Dock pins stable
      services.mac-app-util.enable = lib.mkIf (cfg.autoTrampolines.enable && !cfg.appLinks.enable) true;
      home-manager.sharedModules = lib.mkIf (cfg.autoTrampolines.enable && !cfg.appLinks.enable) [
        inputs.mac-app-util.homeManagerModules.default
      ];

      # Install casks as system packages
      environment.systemPackages = map (cask: pkgs.brewCasks.${cask}) caskNames;

      # Link real app bundles into Applications to avoid trampoline icons
      system.activationScripts.brewNixAppLinks = lib.mkIf cfg.appLinks.enable {
        deps = [ "applications" ];
        text = ''
          echo "brew-nix: linking cask apps into ${cfg.appLinks.targetDir}" >&2
          targetDir="${cfg.appLinks.targetDir}"
          if [ -z "$targetDir" ]; then
            echo "brew-nix: appLinks.targetDir is empty, skipping" >&2
          elif [ -e "$targetDir" ] && [ ! -d "$targetDir" ]; then
            echo "brew-nix: appLinks targetDir exists and is not a directory: $targetDir" >&2
          else
            mkdir -p "$targetDir"

            # Remove old symlinks pointing at the current system apps
            find "$targetDir" -maxdepth 1 -type l -lname "/run/current-system/Applications/*" -exec rm -f {} + || true

            for entry in ${lib.escapeShellArgs appLinkSpecs}; do
              cask="''${entry%%|*}"
              appName="''${entry#*|}"
              appPath=$(find -L /run/current-system/Applications -maxdepth 3 -type d -iname "$appName" | head -n 1)
              if [ -z "$appPath" ]; then
                echo "brew-nix app link: app for cask ''${cask} (''${appName}) not found" >&2
                continue
              fi

              dest="$targetDir/$(basename "$appPath")"
              if [ -e "$dest" ] && [ ! -L "$dest" ]; then
                echo "brew-nix app link: $dest exists and is not a symlink, skipping" >&2
                continue
              fi
              ln -sfn "$appPath" "$dest"
            done
          fi
        '';
      };

      # Avoid stale trampoline apps when app links are enabled
      system.activationScripts.brewNixCleanTrampolines = lib.mkIf cfg.appLinks.enable {
        deps = [ "applications" ];
        text = ''
          if [ -d "/Applications/Nix Trampolines" ]; then
            rm -rf "/Applications/Nix Trampolines" || true
          fi
        '';
      };
    };

  home.ifEnabled = { cfg, ... }:
    let
      caskApps = cfg.casks // cfg.extraCasks;
      appLinkSpecs = map (cask: "${cask}|${caskApps.${cask}}") (lib.attrNames caskApps);
    in
    {
      # Needed to manage Dock entries
      home.packages = lib.optionals cfg.autoDock.enable [ pkgs.dockutil ];

      # Keep Dock pins in sync with current /run/current-system/Applications
      home.activation.brewCaskDockPins = lib.mkIf cfg.autoDock.enable (lib.mkOrder 850 ''
        dockutil="$(command -v dockutil || true)"
        if [ -z "$dockutil" ]; then
          echo "brew-nix Dock pin: dockutil not found, skipping" >&2
          exit 0
        fi

        for entry in ${lib.escapeShellArgs appLinkSpecs}; do
          cask="''${entry%%|*}"
          appName="''${entry#*|}"
          appPath=$(find -L /run/current-system/Applications -maxdepth 3 -type d -iname "$appName" | head -n 1)
          if [ -z "$appPath" ]; then
            echo "brew-nix Dock pin: app for cask ''${cask} (''${appName}) not found" >&2
            continue
          fi

          $dockutil --remove "$appPath" --no-restart >/dev/null 2>&1 || true
          $dockutil --add "$appPath" --replacing "$(basename "$appPath")" --no-restart || true
        done

        # Apply changes once after updates
        killall Dock 2>/dev/null || true
      '');
    };
}

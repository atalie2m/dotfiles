{ delib, lib, inputs, pkgs, ... }:

# Brew-nix integration for managing macOS applications via Nix
delib.module {
  name = "brew-nix";

  options.brew-nix = with delib.options; {
    enable = boolOption false;
    autoDock.enable = boolOption false;
    casks = listOfOption str [
      "rio"
      "keyclu"
      "latest"
      "alacritty"
      "ghostty"
      "wezterm"  # Note: WezTerm has unusual packaging structure in brew-nix.
                 # App is installed as WezTerm-macos-VERSION/WezTerm.app instead of direct WezTerm.app,
                 # making it invisible to Launchpad/Spotlight. CLI works fine via 'wezterm' command.
                 # Can be opened manually: open "/run/current-system/Applications/WezTerm-macos-*/WezTerm.app"
                 # Unlike Rectangle which installs as direct Rectangle.app and appears normally in Launchpad.
      "xcodes-app"
    ];
    extraCasks = listOfOption str [];
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    # Enable brew-nix overlay
    nixpkgs.overlays = [ inputs.brew-nix.overlays.default ];

    # Enable brew-nix
    brew-nix.enable = true;

    # Install casks as system packages
    environment.systemPackages = map (cask: pkgs.brewCasks.${cask}) (cfg.casks ++ cfg.extraCasks);
  };

  home.ifEnabled = { cfg, ... }: let
    casks = cfg.casks ++ cfg.extraCasks;
  in {
    # Needed to manage Dock entries
    home.packages = lib.optionals cfg.autoDock.enable [ pkgs.dockutil ];

    # Keep Dock pins in sync with current /run/current-system/Applications
    home.activation.brewCaskDockPins = lib.mkIf cfg.autoDock.enable (lib.mkOrder 850 ''
      dockutil="$(command -v dockutil || true)"
      if [ -z "$dockutil" ]; then
        echo "brew-nix Dock pin: dockutil not found, skipping" >&2
        exit 0
      fi

      for cask in ${lib.escapeShellArgs casks}; do
        appPath=$(find /run/current-system/Applications -maxdepth 2 -type d -iname "''${cask}.app" | head -n 1)
        if [ -z "$appPath" ]; then
          echo "brew-nix Dock pin: app for cask ''${cask} not found" >&2
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

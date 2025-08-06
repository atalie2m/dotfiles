{ delib, lib, inputs, pkgs, ... }:

# Brew-nix integration for managing macOS applications via Nix
delib.module {
  name = "brew-nix";

  options.brew-nix = with delib.options; {
    enable = boolOption false;
    casks = listOfOption str [
      "rio"
      "keyclu"
      "latest"
      "alacritty"
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
}

{ delib, lib, config, inputs, pkgs, ... }:

# Native Homebrew integration for macOS applications and tools
delib.module {
  name = "homebrew.native";

  options.homebrew.native = with delib.options; {
    enable = boolOption false;

    # Homebrew formulae (CLI tools)
    brews = listOfOption str [];

    # Homebrew casks (GUI applications)
    casks = listOfOption str [];

    # Mac App Store applications (by ID)
    masApps = attrsOfOption int {};

    # Additional Homebrew taps
    taps = listOfOption str [];

    # Brew-nix integration
    enableBrewNix = boolOption true;
    brewNixCasks = listOfOption str [
      "rio"
      "keyclu"
      "latest"
      "alacritty"
      "wezterm"
    ];

    # Cleanup settings
    enableCleanup = boolOption true;
    enableAutoUpdate = boolOption true;
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    # Nixpkgs overlays for brew-nix (if enabled)
    nixpkgs.overlays = lib.mkIf cfg.enableBrewNix [
      inputs.brew-nix.overlays.default
    ];

    # Enable brew-nix
    brew-nix.enable = cfg.enableBrewNix;

    # System packages from brew-nix casks
    environment.systemPackages = lib.mkIf cfg.enableBrewNix (
      map (cask: pkgs.brewCasks.${cask}) cfg.brewNixCasks
    );

    # Standard nix-darwin homebrew configuration
    homebrew = {
      enable = true;

      # Homebrew formulae
      brews = cfg.brews;

      # GUI applications via cask
      casks = cfg.casks;

      # Mac App Store apps
      masApps = cfg.masApps;

      # Additional taps
      taps = cfg.taps;

      # Cleanup and maintenance
      onActivation = {
        cleanup = if cfg.enableCleanup then "zap" else "none";
        autoUpdate = cfg.enableAutoUpdate;
        upgrade = cfg.enableAutoUpdate;
      };
    };
  };
}

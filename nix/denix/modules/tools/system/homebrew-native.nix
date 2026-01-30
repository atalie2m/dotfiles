{ delib, lib, config, inputs, pkgs, ... }:

# Native Homebrew integration for macOS applications and tools
delib.module {
  name = "tools.system.homebrewNative";

  options = with delib; moduleOptions {
    enable = boolOption false;

    # Homebrew formulae (CLI tools)
    brews = listOfOption str [];

    # Homebrew casks (GUI applications)
    casks = listOfOption str [];

    # Mac App Store applications (by ID)
    masApps = attrsOfOption int {};

    # Additional Homebrew taps
    taps = listOfOption str [];

    # Cleanup settings
    enableCleanup = boolOption true;
    enableAutoUpdate = boolOption true;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.system.homebrewNative.enable = lib.mkDefault parent.enable;
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    # Standard nix-darwin homebrew configuration
    homebrew = {
      enable = true;

      # Homebrew formulae, casks, Mac App Store apps, and taps
      inherit (cfg) brews casks masApps taps;

      # Cleanup and maintenance
      onActivation = {
        cleanup = if cfg.enableCleanup then "zap" else "none";
        autoUpdate = cfg.enableAutoUpdate;
        upgrade = cfg.enableAutoUpdate;
      };
    };
  };
}

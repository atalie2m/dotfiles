{ dotmod, config, ... }:

# Native Homebrew integration for macOS applications and tools.
# Preferred for fast-moving apps/tools that should stay up to date.

(dotmod.mkModule { inherit config; }) {
  path = "tools.system.homebrewNative";

  options = with dotmod; moduleOptions {
    enable = boolOption false;

    # Homebrew formulae (CLI tools, latest-first)
    brews = listOfOption str [ ];

    # Homebrew casks (GUI applications, latest-first)
    casks = listOfOption str [ ];

    # Mac App Store applications (by ID)
    masApps = attrsOfOption int { };

    # Additional Homebrew taps
    taps = listOfOption str [ ];

    # Cleanup settings
    enableCleanup = boolOption true;
    enableAutoUpdate = boolOption true;
  };

  darwinOnEnable = { cfg, myconfig, ... }: {
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

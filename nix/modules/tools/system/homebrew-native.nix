{ dotmod, config, ... }:

# Native Homebrew integration for macOS applications and tools.
# Preferred for fast-moving apps/tools that should stay up to date.

let
  caskName = raw:
    if builtins.isAttrs raw then raw.name or ""
    else raw;

  dedupeCasks = casks:
    let
      folded = builtins.foldl'
        (acc: raw:
          let
            name = caskName raw;
          in
          if !(builtins.isString name) || name == "" then
            acc
          else
            {
              names =
                if builtins.elem name acc.names then
                  acc.names
                else
                  acc.names ++ [ name ];
              items = acc.items // {
                ${name} = raw;
              };
            })
        {
          names = [ ];
          items = { };
        }
        casks;
    in
    map (name: folded.items.${name}) folded.names;
in
(dotmod.mkModule { inherit config; }) {
  path = "tools.system.homebrewNative";

  options = with dotmod; moduleOptions {
    enable = boolOption false;

    # Homebrew formulae (CLI tools, latest-first)
    brews = listOfOption str [ ];

    # Homebrew casks (GUI applications, latest-first). Items may be plain cask
    # names or nix-darwin cask attrsets with per-cask args.
    casks = listOfOption anything [ ];

    # Mac App Store applications (by ID)
    masApps = attrsOfOption int { };

    # Additional Homebrew taps
    taps = listOfOption str [ ];

    # Cleanup settings
    enableCleanup = boolOption false;
    enableAutoUpdate = boolOption true;
  };

  darwinOnEnable = { cfg, myconfig, ... }:
    let
      casks = dedupeCasks cfg.casks;
    in
    {
      # Standard nix-darwin homebrew configuration
      homebrew = {
        enable = true;

        # Homebrew formulae, casks, Mac App Store apps, and taps
        inherit (cfg) brews masApps taps;
        inherit casks;

        # Cleanup and maintenance
        onActivation = {
          cleanup = if cfg.enableCleanup then "zap" else "none";
          autoUpdate = cfg.enableAutoUpdate;
          upgrade = cfg.enableAutoUpdate;
        };
      };
    };
}

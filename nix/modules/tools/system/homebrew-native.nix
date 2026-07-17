{ dotmod, config, lib, repoPaths, ... }:

# Native Homebrew integration for macOS applications and tools.
# Preferred for fast-moving apps/tools that should stay up to date.

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");

  caskName = raw:
    if builtins.isAttrs raw then raw.name or ""
    else raw;

  enabledAt = optionPath:
    lib.attrByPath optionPath false config;

  hostHasFullXcode =
    let
      value = lib.attrByPath [ "myconfig" "hostContext" "machine" "extra" "fullXcode" ] false config;
    in
    builtins.isBool value && value;

  specAvailableForHost = spec:
    !(spec.requiresFullXcode or false) || hostHasFullXcode;

  specEnabled = spec:
    enabledAt spec.optionPath && specAvailableForHost spec;

  specs = builtins.attrValues homebrewOwnership;

  namesFor = field: selectedSpecs:
    lib.unique (lib.concatMap (spec: spec.${field} or [ ]) selectedSpecs);

  masIdsFor = selectedSpecs:
    lib.unique (lib.concatMap (spec: builtins.attrNames (spec.masApps or { })) selectedSpecs);

  knownBrews = namesFor "brews" specs;
  enabledBrews = namesFor "brews" (lib.filter specEnabled specs);
  knownCasks = namesFor "casks" specs;
  enabledCasks = namesFor "casks" (lib.filter specEnabled specs);
  knownTaps = namesFor "taps" specs;
  enabledTaps = namesFor "taps" (lib.filter specEnabled specs);
  knownMasIds = masIdsFor specs;
  enabledMasIds = masIdsFor (lib.filter specEnabled specs);

  keepRegistryOwnedName = knownNames: enabledNames: name:
    name == "" || !(builtins.elem name knownNames) || builtins.elem name enabledNames;

  filterRegistryOwnedList = knownNames: enabledNames: nameOf: values:
    lib.filter
      (raw:
        let
          name = nameOf raw;
        in
        keepRegistryOwnedName knownNames enabledNames name)
      values;

  filterRegistryOwnedAttrs = knownNames: enabledNames: values:
    lib.filterAttrs
      (name: _: keepRegistryOwnedName knownNames enabledNames name)
      values;

  keepNotDenied = deniedNames: name:
    name == "" || !(builtins.elem name deniedNames);

  filterDeniedList = deniedNames: nameOf: values:
    lib.filter
      (raw:
        let
          name = nameOf raw;
        in
        keepNotDenied deniedNames name)
      values;

  filterDeniedAttrs = deniedNames: values:
    lib.filterAttrs
      (name: _: keepNotDenied deniedNames name)
      values;

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
    deniedBrews = listOfOption str [ ];

    # Homebrew casks (GUI applications, latest-first). Items may be plain cask
    # names or nix-darwin cask attrsets with per-cask args.
    casks = listOfOption anything [ ];
    deniedCasks = listOfOption str [ ];

    # Mac App Store applications (by ID)
    masApps = attrsOfOption int { };
    deniedMasApps = listOfOption str [ ];

    # Additional Homebrew taps
    taps = listOfOption str [ ];
    deniedTaps = listOfOption str [ ];

    # Cleanup settings
    enableCleanup = boolOption false;
    # Keep routine darwin activation idempotent. Explicit maintenance can run
    # `brew bundle upgrade` against the generated Brewfile.
    enableAutoUpdate = boolOption false;
  };

  darwinOnEnable = { cfg, myconfig, ... }:
    let
      brews = filterDeniedList cfg.deniedBrews (raw: raw) (
        filterRegistryOwnedList knownBrews enabledBrews (raw: raw) cfg.brews
      );
      casks = dedupeCasks (
        filterDeniedList cfg.deniedCasks caskName (
          filterRegistryOwnedList knownCasks enabledCasks caskName cfg.casks
        )
      );
      taps = filterDeniedList cfg.deniedTaps (raw: raw) (
        filterRegistryOwnedList knownTaps enabledTaps (raw: raw) cfg.taps
      );
      masApps = filterDeniedAttrs cfg.deniedMasApps (
        filterRegistryOwnedAttrs knownMasIds enabledMasIds cfg.masApps
      );
      hasCask = name:
        builtins.any (raw: caskName raw == name) casks;
    in
    {
      # Standard nix-darwin homebrew configuration
      homebrew = {
        enable = true;

        # Homebrew formulae, casks, Mac App Store apps, and taps
        inherit brews casks masApps taps;

        # Make an explicit `brew bundle upgrade` use the declarative Brewfile.
        global.brewfile = true;

        # Cleanup and maintenance
        onActivation = {
          cleanup = if cfg.enableCleanup then "zap" else "none";
          autoUpdate = cfg.enableAutoUpdate;
          upgrade = cfg.enableAutoUpdate;
        };
      };

      system.activationScripts.homebrew.text = lib.mkIf (hasCask "codex") (lib.mkBefore ''
        # Codex cask preflight
        # A previous host-local workaround may leave /opt/homebrew/bin/codex as
        # a regular copied binary while the cask itself is no longer installed.
        # Homebrew then refuses to install the cask before the cask postinstall
        # repair hook can run. Move only that stale unmanaged shape aside.
        for prefix in /opt/homebrew /usr/local; do
          brew_bin="$prefix/bin/brew"
          codex_bin="$prefix/bin/codex"

          if [ -x "$brew_bin" ] \
            && ! "$brew_bin" list --cask codex >/dev/null 2>&1 \
            && [ -f "$codex_bin" ] \
            && [ ! -L "$codex_bin" ]; then
            backup="$codex_bin.dotfiles-stale-$(/bin/date +%Y%m%d%H%M%S)"
            echo >&2 "dotfiles: moving stale unmanaged Codex binary: $codex_bin -> $backup"
            /bin/mv "$codex_bin" "$backup"
          fi
        done
      '');
    };
}

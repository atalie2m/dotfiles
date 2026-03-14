{ lib }:

let
  getPlatform = myconfig:
    myconfig.facts.user.platform or myconfig.constants.platform or "";
  normalizeCatalogPkgPath = value:
    if value == null then null
    else if builtins.isList value then value
    else [ value ];
  selectedCatalogPkgField = systemName: spec:
    if systemName == "darwin" then
      if spec ? pkgDarwin then "pkgDarwin"
      else if spec ? pkg then "pkg"
      else null
    else if systemName == "linux" then
      if spec ? pkgLinux then "pkgLinux"
      else if spec ? pkg then "pkg"
      else null
    else if spec ? pkg then
      "pkg"
    else
      null;
  selectedCatalogPkgPath = systemName: spec:
    let
      field = selectedCatalogPkgField systemName spec;
    in
    if field == null then null else normalizeCatalogPkgPath spec.${field};
  selectedCatalogPkgDescription = systemName: spec:
    let
      field = selectedCatalogPkgField systemName spec;
      path = selectedCatalogPkgPath systemName spec;
      missingFields =
        if systemName == "darwin" then "pkgDarwin or pkg"
        else if systemName == "linux" then "pkgLinux or pkg"
        else "pkg";
    in
    if field == null then
      "${missingFields} is not set"
    else
      "${field}=pkgs.${lib.concatStringsSep "." (map builtins.toString path)}";
  mkHostContext = { inputs, name, machineKey, resolveHomeDirectory, resolvePlatform }:
    let
      facts = import (inputs.local + "/facts.nix");
      user = facts.user or { };
      machines = facts.machines or { };
      machine = machines.${machineKey} or { };
      username = user.username or "";
      homeDirectory = resolveHomeDirectory {
        inherit lib user machine username;
      };
      platform = resolvePlatform {
        inherit lib user machine;
      };
      stateVersion = user.stateVersion or { };
      effectiveUser = {
        inherit username homeDirectory platform stateVersion;
        fullName = user.fullName or "";
        email = user.email or "";
        configDirectory = user.configDirectory or ".config";
        systemType = user.systemType or "";
        architecture = user.architecture or "";
      };
    in
    assert lib.assertMsg (username != "") "facts.user.username is required for ${name}";
    {
      inherit facts user machines machine username homeDirectory platform stateVersion effectiveUser;
    };
  riceProfiles = {
    base = {
      inherits = [ ];
      myconfig = {
        system.nix.enable = true;
        tools.core.enable = true;
        tools.shell.enable = true;
        tools.dev.git.enable = true;
        tools.security.enable = true;
      };
    };

    darwin = {
      inherits = [ "base" ];
      myconfig = {
        tools.system.nixHomebrew.enable = true;
        tools.system.homebrewNative.enable = true;
        tools.system.hostnames.enable = true;
        tools.system.fonts.enable = true;
        tools.system.macosUi.enable = true;
      };
    };

    dev = {
      inherits = [ "base" ];
      myconfig = {
        tools.aiCodingAgent.enable = true;
        tools.dev.enable = true;
        tools.editor.emacs.enable = true;
        tools.editor.neovim.enable = true;
        tools.editor.vscode.enable = true;
        tools.dev.git.delta.enable = true;
        tools.shell.defaultShell = "zsh";
        tools.shell.atuin.enable = true;
        tools.shell.direnv.enable = true;
        tools.shell.fzf.enable = true;
        tools.shell.fzfTab.enable = true;
        tools.shell.zoxide.enable = true;
        tools.system.karabiner.enable = true;
        tools.system.aerospace.enable = true;
        tools.system.keyclu.enable = true;
        tools.system.latestApp.enable = true;
        tools.system.xcodesApp.enable = true;
        tools.terminal.alacritty.enable = true;
        tools.terminal.ghostty.enable = true;
        tools.terminal.wezterm.enable = true;
        tools.terminal.rio.enable = true;
      };
    };

    partial = {
      inherits = [ "base" "darwin" "dev" ];
      myconfig = {
        tools.editor.vscode.sync.enable = false;
      };
    };

    ultra = {
      inherits = [ "base" "darwin" "dev" ];
      myconfig = {
        tools.dev.ansible.enable = false;
        tools.dev.go.enable = false;
        tools.dev.nodejs.enable = false;
        tools.dev.opentofu.enable = false;
        tools.dev.terraform.enable = false;

        tools.dev.gitAbsorb.enable = true;
        tools.dev.gnugrep.enable = true;
        tools.dev.gnused.enable = true;
        # Keep git-lfs enabled as requested; this is managed by the git module.
        tools.dev.git.lfs.enable = true;
      };
    };

    pro = {
      inherits = [ "base" "darwin" ];
      myconfig = {
        tools.aiCodingAgent.enable = true;
        tools.dev.enable = true;
        tools.editor.emacs.enable = true;
        tools.editor.neovim.enable = true;
        tools.editor.vscode.sync.enable = false;
        tools.dev.git.delta.enable = true;
        tools.shell.defaultShell = "zsh";
        tools.shell.atuin.enable = true;
        tools.shell.direnv.enable = true;
        tools.shell.fzf.enable = true;
        tools.shell.fzfTab.enable = true;
        tools.shell.zoxide.enable = true;
        tools.system.karabiner.enable = true;
        tools.system.aerospace.enable = true;
        tools.system.keyclu.enable = true;
        tools.system.latestApp.enable = true;
        tools.system.xcodesApp.enable = true;
        tools.terminal.alacritty.enable = true;
        tools.terminal.ghostty.enable = true;
        tools.terminal.wezterm.enable = true;
        tools.terminal.rio.enable = true;

        tools.dev.ansible.enable = false;
        tools.dev.go.enable = false;
        tools.dev.nodejs.enable = false;
        tools.dev.opentofu.enable = false;
        tools.dev.terraform.enable = false;

        tools.dev.gitAbsorb.enable = true;
        tools.dev.gnugrep.enable = true;
        tools.dev.gnused.enable = true;
        # Keep git-lfs enabled as requested; this is managed by the git module.
        tools.dev.git.lfs.enable = true;
      };
    };

    minimum = {
      inherits = [ "base" ];
      myconfig = { };
    };
  };
in
rec {
  inherit mkHostContext riceProfiles;

  mkEnableDefault = optionPath: { parent, ... }:
    lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault parent.enable);

  mkEnableDefaults = optionPaths: args:
    lib.mkMerge (map (optionPath: (lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault args.parent.enable))) optionPaths);

  requireHomebrew = { taps ? [ ], brews ? [ ], casks ? [ ], masApps ? { } }:
    lib.mkMerge [
      {
        # Prefer enabling Homebrew when a tool explicitly requires it.
        # Keep this weaker than explicit user values, but stronger than inherited mkDefault false.
        tools.system.nixHomebrew.enable = lib.mkOverride 900 true;
        tools.system.homebrewNative.enable = lib.mkOverride 900 true;
      }
      (lib.optionalAttrs (taps != [ ]) {
        tools.system.homebrewNative.taps = lib.mkAfter taps;
      })
      (lib.optionalAttrs (brews != [ ]) {
        tools.system.homebrewNative.brews = lib.mkAfter brews;
      })
      (lib.optionalAttrs (casks != [ ]) {
        tools.system.homebrewNative.casks = lib.mkAfter casks;
      })
      (lib.optionalAttrs (masApps != { }) {
        tools.system.homebrewNative.masApps = masApps;
      })
    ];

  requireUnfree = packages:
    lib.mkMerge [
      {
        nixpkgs.unfree.enable = lib.mkOverride 900 true;
        nixpkgs.unfree.allowAll = lib.mkOverride 900 false;
      }
      (lib.optionalAttrs (packages != [ ]) {
        nixpkgs.unfree.packages = lib.mkAfter packages;
      })
    ];

  resolveCatalogPkg =
    { pkgs
    , systemName
    , spec
    }:
    let
      path = selectedCatalogPkgPath systemName spec;
    in
    if path == null then null else lib.attrByPath path null pkgs;

  nixCatalogFailureMessage =
    { toolKey
    , systemName
    , spec
    }:
    "catalog entry ${toolKey} is enabled on ${systemName} but did not resolve to a Nix package (${selectedCatalogPkgDescription systemName spec})";

  hasHomebrewInstallPayload = spec:
    (spec.brews or [ ]) != [ ]
    || (spec.casks or [ ]) != [ ]
    || (spec.masApps or { }) != { };

  homebrewCatalogFailureMessage = { toolKey }:
    "Homebrew catalog entry ${toolKey} must declare at least one of brews, casks, or masApps.";

  ifDarwin = myconfig: attrs:
    lib.mkIf (lib.hasSuffix "-darwin" (getPlatform myconfig)) attrs;

  ifLinux = myconfig: attrs:
    lib.mkIf (lib.hasSuffix "-linux" (getPlatform myconfig)) attrs;
}

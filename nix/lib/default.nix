{ lib }:

let
  getPlatform = myconfig:
    myconfig.facts.user.platform or myconfig.constants.platform or "";
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

    full = {
      inherits = [ "base" "darwin" "dev" ];
      myconfig = { };
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

  ifDarwin = myconfig: attrs:
    lib.mkIf (lib.hasSuffix "-darwin" (getPlatform myconfig)) attrs;

  ifLinux = myconfig: attrs:
    lib.mkIf (lib.hasSuffix "-linux" (getPlatform myconfig)) attrs;
}

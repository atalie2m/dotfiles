{ inputs, dotlib, repoPaths }:

let
  lib = inputs.nixpkgs.lib;
  dotmod = import ../lib/module-helpers.nix { inherit lib; };
  homeDotmod = import ../lib/module-helpers.nix {
    inherit lib;
    mode = "home";
  };
  darwinCatalog = import ../catalog/darwin { inherit lib; };
  linuxCatalog = import ../catalog/linux { inherit lib; };
  nixCatalog = import ../catalog/tools/nixpkgs.nix;
  localPackagesOverlay = import ../pkgs/overlay.nix;
  baseRawFacts = import (inputs.local + "/facts.nix");
  runtimeFactsPath = inputs.local + "/runtime.nix";
  runtimeFacts =
    if builtins.pathExists runtimeFactsPath then
      import runtimeFactsPath
    else
      { };
  rawFacts = lib.recursiveUpdate baseRawFacts runtimeFacts;
  normalizedFacts = dotlib.normalizeRawFacts rawFacts;
  username = normalizedFacts.user.username;
  catalogUnfreePackages = lib.unique (lib.concatMap (spec: spec.unfree or [ ]) (builtins.attrValues nixCatalog));
  allowUnfreePackages = lib.unique (catalogUnfreePackages ++ [ "zsh-abbr" ]);

  codexHomebrewBinCopyCask = {
    name = "codex";
    postinstall = ''
      prefix=$(brew --prefix)
      binary=$(/usr/bin/find $prefix/Caskroom/codex -type f -name 'codex-*apple-darwin' -print -quit)
      if [ x$binary != x ]; then
        /bin/rm -f $prefix/bin/codex
        /usr/bin/install -m 0755 $binary $prefix/bin/codex
        /usr/bin/xattr -c $prefix/bin/codex 2>/dev/null || true
      fi
    '';
  };

  hostLocalMyconfigFor = host:
    let
      codexExtra = (host.machine.extra.codex or { });
      useCodexBinCopyWorkaround = codexExtra.homebrewBinCopyWorkaround or false;
    in
    lib.optionalAttrs (builtins.isBool useCodexBinCopyWorkaround && useCodexBinCopyWorkaround) {
      tools.aiCodingAgent.codex.enable = lib.mkDefault true;
      tools.system.homebrewNative.casks = lib.mkAfter [ codexHomebrewBinCopyCask ];
    };

  mkHomeManagerModule = host: { ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];

    nix.package = lib.mkDefault inputs.nixpkgs.legacyPackages.${host.system}.nix;

    home = {
      inherit (host.user) username homeDirectory;
      stateVersion = host.user.stateVersion.home;
    };

    targets.darwin = {
      copyApps.enable = false;
      linkApps.enable = true;
    };
  };

  mkDarwinTarget =
    hostName: profileName:
    let
      hostSpec = darwinCatalog.hosts.${hostName};
      host = dotlib.buildHostModel {
        inherit rawFacts;
        inherit (hostSpec) name machineKey system;
      };
      profileMyconfig = darwinCatalog.profiles.${profileName};
      hostExtraMyconfig = hostSpec.extraMyconfig or { };
      hostLocalMyconfig = hostLocalMyconfigFor host;
      hostPolicyMyconfig =
        if hostName == "work_mac" then
          darwinCatalog.policyLib.forcedOverridesFor
            {
              inherit profileMyconfig hostExtraMyconfig;
              policy = darwinCatalog.workPolicy;
            }
        else
          { };
      nixPackage = inputs.nixpkgs.legacyPackages.${host.system}.nix;
      userName = host.user.username;
      homeDir = host.user.homeDirectory;
    in
    inputs.nix-darwin.lib.darwinSystem {
      system = host.system;
      specialArgs = {
        inherit inputs dotlib dotmod repoPaths;
        catalog = darwinCatalog;
      };
      modules = [
        inputs.sops-nix.darwinModules.sops
        inputs.home-manager.darwinModules.home-manager
        ../modules
        ({ ... }: {
          nix.package = lib.mkDefault nixPackage;
          nixpkgs.hostPlatform = host.system;
          nixpkgs.overlays = [ localPackagesOverlay ];
          system.stateVersion = host.user.stateVersion.darwin;
          system.primaryUser = userName;
          home-manager.backupFileExtension = "hm-backup";
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs dotlib repoPaths;
          };
          home-manager.users.${userName} = mkHomeManagerModule host;

          users.users.${userName} = {
            name = userName;
            home = homeDir;
          };

          myconfig = lib.mkMerge [
            {
              hostContext = host;
              profile = {
                name = profileName;
                available = darwinCatalog.profileNames;
              };
            }
            profileMyconfig
            hostExtraMyconfig
            hostLocalMyconfig
            hostPolicyMyconfig
          ];
        })
      ];
    };

  mkDarwinHostTargets = hostName:
    builtins.listToAttrs (
      map
        (profileName: {
          name = darwinCatalog.targetNameFor hostName profileName;
          value = mkDarwinTarget hostName profileName;
        })
        darwinCatalog.hosts.${hostName}.supportedProfiles
    );

  linuxHomeManagerModulePaths = [
    ../modules/shared/host.nix
    ../modules/shared/nixpkgs-unfree.nix
    ../modules/shared/profile.nix
    ../modules/shared/system-nix.nix
    ../modules/tools/catalog.nix
    ../modules/tools/core.nix
    ../modules/tools/dev.nix
    ../modules/tools/dev/git.nix
    ../modules/tools/editor.nix
    ../modules/tools/editor/neovim.nix
    ../modules/tools/network/mosh.nix
    ../modules/tools/profile-defaults.nix
    ../modules/tools/profile-groups.nix
    ../modules/tools/security.nix
    ../modules/tools/security/gpg.nix
    ../modules/tools/security/sops.nix
    ../modules/tools/shell.nix
    ../modules/tools/shell/atuin.nix
    ../modules/tools/shell/bash.nix
    ../modules/tools/shell/direnv.nix
    ../modules/tools/shell/fzf-tab.nix
    ../modules/tools/shell/fzf.nix
    ../modules/tools/shell/pure.nix
    ../modules/tools/shell/zoxide.nix
    ../modules/tools/shell/zsh.nix
    ../modules/tools/terminal.nix
    ../modules/tools/terminal/tmux.nix
  ];

  mkLinuxPkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) allowUnfreePackages;
      overlays = [ localPackagesOverlay ];
    };

  mkHomeManagerTarget =
    hostName: profileName:
    let
      hostSpec = linuxCatalog.hosts.${hostName};
      host = dotlib.buildHostModel {
        inherit rawFacts;
        inherit (hostSpec) name machineKey system;
      };
      pkgs = mkLinuxPkgs host.system;
      profileMyconfig = linuxCatalog.profiles.${profileName};
      hostExtraMyconfig = hostSpec.extraMyconfig or { };
    in
    inputs.home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      extraSpecialArgs = {
        inherit inputs dotlib repoPaths;
        catalog = linuxCatalog;
        dotmod = homeDotmod;
      };
      modules = [
        inputs.sops-nix.homeManagerModules.sops
      ] ++ linuxHomeManagerModulePaths ++ [
        ({ lib, ... }: {
          assertions = [
            {
              assertion = host.os == "linux";
              message = "homeConfigurations.${linuxCatalog.targetNameFor hostName profileName} must be a Linux target.";
            }
          ];

          home = {
            inherit (host.user) username homeDirectory;
            stateVersion = host.user.stateVersion.home;
          };

          programs.home-manager.enable = true;

          nix.package = lib.mkDefault pkgs.nix;

          myconfig = lib.mkMerge [
            {
              hostContext = host;
              profile = {
                name = profileName;
                available = linuxCatalog.profileNames;
              };
            }
            profileMyconfig
            hostExtraMyconfig
          ];
        })
      ];
    };

  mkHomeManagerHostTargets = hostName:
    builtins.listToAttrs (
      map
        (profileName: {
          name = linuxCatalog.targetNameFor hostName profileName;
          value = mkHomeManagerTarget hostName profileName;
        })
        linuxCatalog.hosts.${hostName}.supportedProfiles
    );

  darwinConfigurations =
    if username == null then
      throw "facts.user.username is required (set in ~/.config/dotfiles/facts.nix or override inputs.local)"
    else
      lib.foldl'
        (acc: hostName: acc // mkDarwinHostTargets hostName)
        { }
        (builtins.attrNames darwinCatalog.hosts);

  homeConfigurations =
    if username == null then
      throw "facts.user.username is required (set in ~/.config/dotfiles/facts.nix or override inputs.local)"
    else
      lib.foldl'
        (acc: hostName: acc // mkHomeManagerHostTargets hostName)
        { }
        (builtins.attrNames linuxCatalog.hosts);
in
{
  inherit darwinConfigurations homeConfigurations linuxHomeManagerModulePaths;
}

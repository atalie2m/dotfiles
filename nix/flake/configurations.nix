{ inputs, dotlib, repoPaths }:

let
  lib = inputs.nixpkgs.lib;
  dotmod = import ../lib/module-helpers.nix { inherit lib; };
  catalog = import ../catalog/darwin { inherit lib; };
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

  mkTarget =
    hostName: profileName:
    let
      hostSpec = catalog.hosts.${hostName};
      host = dotlib.buildHostModel {
        inherit rawFacts;
        inherit (hostSpec) name machineKey system;
      };
      profileMyconfig = catalog.profiles.${profileName};
      hostExtraMyconfig = hostSpec.extraMyconfig or { };
      hostLocalMyconfig = hostLocalMyconfigFor host;
      hostPolicyMyconfig =
        if hostName == "work_mac" then
          catalog.policyLib.forcedOverridesFor
            {
              inherit profileMyconfig hostExtraMyconfig;
              policy = catalog.workPolicy;
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
        inherit inputs dotlib dotmod repoPaths catalog;
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
                available = catalog.profileNames;
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

  mkHostTargets = hostName:
    builtins.listToAttrs (
      map
        (profileName: {
          name = catalog.targetNameFor hostName profileName;
          value = mkTarget hostName profileName;
        })
        catalog.hosts.${hostName}.supportedProfiles
    );

  darwinConfigurations =
    if username == null then
      throw "facts.user.username is required (set in ~/.config/dotfiles/facts.nix or override inputs.local)"
    else
      lib.foldl'
        (acc: hostName: acc // mkHostTargets hostName)
        { }
        (builtins.attrNames catalog.hosts);
in
{
  inherit darwinConfigurations;
}

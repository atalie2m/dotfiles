{ delib, lib, dotlib, inputs, ... }:

{ name
, rice
, machineKey
, system
, extraMyconfig ? { }
,
}:

let
  rawFacts = import (inputs.local + "/facts.nix");
  host = dotlib.buildHostModel {
    inherit name machineKey system rawFacts;
  };
  normalizedFacts = dotlib.normalizeRawFacts rawFacts;
  nixPackage = inputs.nixpkgs.legacyPackages.${host.system}.nix;
in
delib.host {
  inherit name rice;
  type = "desktop";
  homeManagerSystem = host.system;

  myconfig = lib.recursiveUpdate
    {
      facts = normalizedFacts;
      hostContext = host;
    }
    extraMyconfig;

  home = { ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];
    nix.package = lib.mkDefault nixPackage;
    home = {
      inherit (host.user) username homeDirectory;
      stateVersion = host.user.stateVersion.home;
    };
    targets.darwin = {
      copyApps.enable = false;
      linkApps.enable = true;
    };
  };

  darwin = { ... }:
    let
      userName = host.user.username;
      homeDir = host.user.homeDirectory;
    in
    {
      imports = [ inputs.sops-nix.darwinModules.sops ];
      nix.package = lib.mkDefault nixPackage;
      system.stateVersion = host.user.stateVersion.darwin;
      nixpkgs.hostPlatform = host.system;
      system.primaryUser = userName;

      users.users.${userName} = {
        name = userName;
        home = homeDir;
      };
    };
}

{ delib, lib, dotlib, inputs, ... }:

{ name
, rice
, machineKey
, system
, extraMyconfig ? { }
, extraHome ? { }
, extraNixos ? { }
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

  home = { ... }:
    lib.recursiveUpdate
      {
        imports = [ inputs.sops-nix.homeManagerModules.sops ];
        nix.package = lib.mkDefault nixPackage;
        home = {
          inherit (host.user) username homeDirectory;
          stateVersion = host.user.stateVersion.home;
        };
      }
      extraHome;

  nixos = { ... }:
    lib.recursiveUpdate
      ({
        imports = [ inputs.sops-nix.nixosModules.sops ];
        system.stateVersion = host.user.stateVersion.nixos;
        nixpkgs.hostPlatform = host.system;
        nix.package = lib.mkDefault nixPackage;
        fileSystems."/" = lib.mkDefault {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub = {
          enable = lib.mkDefault true;
          devices = lib.mkDefault [ "/dev/sda" ];
        };

        users.users.${host.user.username} = {
          isNormalUser = true;
          home = host.user.homeDirectory;
          extraGroups = [ "wheel" ];
        };
      })
      extraNixos;
}

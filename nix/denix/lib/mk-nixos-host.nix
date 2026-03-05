{ delib, lib, inputs, pkgs ? null, ... }:

{ name
, rice
, machineKey
, extraMyconfig ? { }
, extraHome ? { }
, extraNixos ? { }
,
}:

let
  facts = import (inputs.local + "/facts.nix");
  user = facts.user or { };
  machines = facts.machines or { };
  machine = machines.${machineKey} or { };
  username = user.username or "";

  machineHomeDirectory = machine.homeDirectory or "";
  userHomeDirectory = user.homeDirectory or "";
  defaultHomeDirectory = if username != "" then "/home/${username}" else "";
  homeDirectory =
    if machineHomeDirectory != "" then machineHomeDirectory
    else if lib.hasPrefix "/home/" userHomeDirectory then userHomeDirectory
    else defaultHomeDirectory;

  machinePlatform = machine.platform or "";
  userPlatform = user.platform or "";
  platform =
    if machinePlatform != "" then machinePlatform
    else if lib.hasSuffix "-linux" userPlatform then userPlatform
    else "x86_64-linux";

  stateVersion = user.stateVersion or { };
  nixosStateVersion =
    if stateVersion ? nixos && lib.isString stateVersion.nixos && stateVersion.nixos != "" then
      stateVersion.nixos
    else
      "25.05";

  effectiveUser = {
    inherit username homeDirectory platform;
    fullName = user.fullName or "";
    email = user.email or "";
    configDirectory = user.configDirectory or ".config";
    systemType = user.systemType or "";
    architecture = user.architecture or "";
    stateVersion = user.stateVersion or { };
  };
in
assert lib.assertMsg (username != "") "facts.user.username is required for ${name}";
delib.host {
  inherit name rice;
  type = "desktop";
  homeManagerSystem = platform;

  myconfig = lib.recursiveUpdate
    {
      facts = {
        user = effectiveUser;
        inherit machine machines;
        binaryCaches = facts.binaryCaches or { };
      };
    }
    extraMyconfig;

  home = { ... }:
    lib.recursiveUpdate
      {
        imports = [ inputs.sops-nix.homeManagerModules.sops ];
        home = {
          inherit username homeDirectory;
          stateVersion = stateVersion.home or "25.05";
        };
      }
      extraHome;

  nixos = { ... }:
    lib.recursiveUpdate
      ({
        imports = [ inputs.sops-nix.nixosModules.sops ];
        system.stateVersion = nixosStateVersion;
        nixpkgs.hostPlatform = platform;
        fileSystems."/" = lib.mkDefault {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub = {
          enable = lib.mkDefault true;
          devices = lib.mkDefault [ "/dev/sda" ];
        };

        users.users.${username} = {
          isNormalUser = true;
          home = homeDirectory;
          extraGroups = [ "wheel" ];
        };
      } // lib.optionalAttrs (pkgs != null) {
        nix.package = pkgs.nix;
      })
      extraNixos;
}

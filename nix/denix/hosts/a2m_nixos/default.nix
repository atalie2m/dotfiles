{ delib, pkgs, lib, inputs, ... }:

let
  facts = import (inputs.local + "/facts.nix");
  user = facts.user or { };
  machines = facts.machines or { };
  machine = machines.a2m_nixos or { };
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
assert lib.assertMsg (username != "") "facts.user.username is required for a2m_nixos";
delib.host {
  name = "a2m_nixos";
  rice = "minimum";
  type = "desktop";
  homeManagerSystem = platform;

  myconfig.facts = {
    user = effectiveUser;
    inherit machine machines;
    binaryCaches = facts.binaryCaches or { };
  };

  home = { ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];
    home = {
      inherit username homeDirectory;
      stateVersion = stateVersion.home or "25.05";
    };
  };

  nixos = { ... }: {
    imports = [ inputs.sops-nix.nixosModules.sops ];
    system.stateVersion = nixosStateVersion;
    nixpkgs.hostPlatform = platform;

    # Minimal boot/filesystem placeholders so `nixosConfigurations` evaluates/builds.
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    boot.loader.grub = {
      enable = true;
      device = "/dev/vda";
    };

    nix.package = pkgs.nix;

    users.users.${username} = {
      isNormalUser = true;
      home = homeDirectory;
      extraGroups = [ "wheel" ];
    };
  };
}

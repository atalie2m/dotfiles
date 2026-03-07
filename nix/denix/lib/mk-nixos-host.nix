{ delib, lib, dotlib, inputs, ... }:

{ name
, rice
, machineKey
, extraMyconfig ? { }
, extraHome ? { }
, extraNixos ? { }
,
}:

let
  context = dotlib.mkHostContext {
    inherit inputs name machineKey;
    resolveHomeDirectory = { username, user, machine, ... }:
      let
        machineHomeDirectory = machine.homeDirectory or "";
        userHomeDirectory = user.homeDirectory or "";
        defaultHomeDirectory = if username != "" then "/home/${username}" else "";
      in
      if machineHomeDirectory != "" then machineHomeDirectory
      else if lib.hasPrefix "/home/" userHomeDirectory then userHomeDirectory
      else defaultHomeDirectory;
    resolvePlatform = { machine, user, ... }:
      let
        machinePlatform = machine.platform or "";
        userPlatform = user.platform or "";
      in
      if machinePlatform != "" then machinePlatform
      else if lib.hasSuffix "-linux" userPlatform then userPlatform
      else "x86_64-linux";
  };
  nixosStateVersion =
    if context.stateVersion ? nixos && lib.isString context.stateVersion.nixos && context.stateVersion.nixos != "" then
      context.stateVersion.nixos
    else
      "25.11";
  nixPackage = inputs.nixpkgs.legacyPackages.${context.platform}.nix;
in
delib.host {
  inherit name rice;
  type = "desktop";
  homeManagerSystem = context.platform;

  myconfig = lib.recursiveUpdate
    {
      facts = {
        user = context.effectiveUser;
        inherit (context) machine machines;
        binaryCaches = context.facts.binaryCaches or { };
      };
    }
    extraMyconfig;

  home = { ... }:
    lib.recursiveUpdate
      {
        imports = [ inputs.sops-nix.homeManagerModules.sops ];
        nix.package = lib.mkDefault nixPackage;
        home = {
          inherit (context) username homeDirectory;
          stateVersion = context.stateVersion.home or "25.11";
        };
      }
      extraHome;

  nixos = { ... }:
    lib.recursiveUpdate
      ({
        imports = [ inputs.sops-nix.nixosModules.sops ];
        system.stateVersion = nixosStateVersion;
        nixpkgs.hostPlatform = context.platform;
        nix.package = lib.mkDefault nixPackage;
        fileSystems."/" = lib.mkDefault {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
        };
        boot.loader.grub = {
          enable = lib.mkDefault true;
          devices = lib.mkDefault [ "/dev/sda" ];
        };

        users.users.${context.username} = {
          isNormalUser = true;
          home = context.homeDirectory;
          extraGroups = [ "wheel" ];
        };
      })
      extraNixos;
}

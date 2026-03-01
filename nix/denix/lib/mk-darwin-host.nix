{ delib, lib, inputs, pkgs ? null, ... }:

{ name
, rice
, machineKey
, extraMyconfig ? { }
,
}:

let
  facts = import (inputs.local + "/facts.nix");
  user = facts.user or { };
  machines = facts.machines or { };
  machine = machines.${machineKey} or { };
  username = user.username or "";
  defaultHomeDirectory = if username != "" then "/Users/${username}" else "";
  homeDirectory = user.homeDirectory or defaultHomeDirectory;
  factsPlatform = user.platform or "";
  platform = if factsPlatform != "" then factsPlatform else "aarch64-darwin";
  effectiveUser = {
    inherit username homeDirectory platform;
    fullName = user.fullName or "";
    email = user.email or "";
    configDirectory = user.configDirectory or ".config";
    systemType = user.systemType or "";
    architecture = user.architecture or "";
    stateVersion = user.stateVersion or { };
  };
  stateVersion = user.stateVersion or { };
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

  home = { ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];
    home = {
      inherit username homeDirectory;
      stateVersion = stateVersion.home or "25.05";
    };
  };

  darwin = { ... }:
    let
      userName = username;
      homeDir = homeDirectory;
    in
    {
      imports = [ inputs.sops-nix.darwinModules.sops ];
      system.stateVersion = stateVersion.darwin or 6;
      nixpkgs.hostPlatform = platform;
      system.primaryUser = userName;

      users.users.${userName} = {
        name = userName;
        home = homeDir;
      };
    } // lib.optionalAttrs (pkgs != null) {
      nix.package = pkgs.nix;
    };
}

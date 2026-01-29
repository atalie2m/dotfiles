{ delib, pkgs, lib, inputs, ... }:

let
  facts = import (inputs.local + "/facts.nix");
  user = facts.user or {};
  machines = facts.machines or {};
  machine = machines.mn_mac or {};
  username = user.username or "";
  homeDirectory = user.homeDirectory or "";
  platform = user.platform or pkgs.stdenv.hostPlatform.system;
  stateVersion = user.stateVersion or {};
in
assert lib.assertMsg (username != "") "facts.user.username is required for mn_mac";
assert lib.assertMsg (homeDirectory != "") "facts.user.homeDirectory is required for mn_mac";
delib.host {
  name = "mn_mac";
  rice = "mn"; # default rice; can switch to -minimum
  type = "desktop";
  homeManagerSystem = platform;

  myconfig.facts = {
    inherit user machine machines;
    binaryCaches = facts.binaryCaches or {};
  };

  home = { name, cfg, myconfig, ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];
    home = {
      inherit username homeDirectory;
      stateVersion = stateVersion.home or "25.05";
    };
  };

  darwin = { name, cfg, myconfig, ... }: let
    userName = username;
    homeDir = homeDirectory;
  in {
    imports = [ inputs.sops-nix.darwinModules.sops ];
    system.stateVersion = stateVersion.darwin or 6;
    nixpkgs.hostPlatform = platform;

    nix.package = pkgs.nix;

    # nix-darwin requires setting the primary user for user-scoped options (e.g., Homebrew)
    system.primaryUser = userName;

    users.users.${userName} = {
      name = userName;
      home = homeDir;
    };
  };
}

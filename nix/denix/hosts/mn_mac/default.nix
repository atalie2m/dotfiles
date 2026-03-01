{ delib, pkgs, lib, inputs, ... }:

let
  facts = import (inputs.local + "/facts.nix");
  user = facts.user or { };
  machines = facts.machines or { };
  machine = machines.mn_mac or { };
  username = user.username or "";
  defaultHomeDirectory =
    if username != "" && pkgs.stdenv.isDarwin then "/Users/${username}" else "";
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
assert lib.assertMsg (username != "") "facts.user.username is required for mn_mac";
delib.host {
  name = "mn_mac";
  rice = "mn"; # default rice; can switch to -minimum
  type = "desktop";
  homeManagerSystem = platform;

  myconfig.facts = {
    user = effectiveUser;
    inherit machine machines;
    binaryCaches = facts.binaryCaches or { };
  };

  home = { name, cfg, myconfig, ... }: {
    imports = [ inputs.sops-nix.homeManagerModules.sops ];
    home = {
      inherit username homeDirectory;
      stateVersion = stateVersion.home or "25.05";
    };
  };

  darwin = { name, cfg, myconfig, ... }:
    let
      userName = username;
      homeDir = homeDirectory;
    in
    {
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

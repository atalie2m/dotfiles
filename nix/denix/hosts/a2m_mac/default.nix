{ delib, pkgs, lib, inputs, ... }:

let
  facts = import (inputs.local + "/facts.nix");
  user = facts.user or { };
  machines = facts.machines or { };
  machine = machines.a2m_mac or { };
  username = user.username or "";
  homeDirectory = user.homeDirectory or "";
  platform = user.platform or pkgs.stdenv.hostPlatform.system;
  stateVersion = user.stateVersion or { };
in
assert lib.assertMsg (username != "") "facts.user.username is required for a2m_mac";
assert lib.assertMsg (homeDirectory != "") "facts.user.homeDirectory is required for a2m_mac";
delib.host {
  name = "a2m_mac";
  rice = "full"; # default rice; can switch to -minimum
  type = "desktop";
  homeManagerSystem = platform;

  myconfig = {
    facts = {
      inherit user machine machines;
      binaryCaches = facts.binaryCaches or { };
    };
    tools.terminal.tmux.enable = true;
    tools.system.macAppUtil = {
      enable = true;
      systemService.enable = false;
      homeTrampolines.syncDock = true;
      homeTrampolines.timeoutSeconds = 15;
    };
    tools.editor.vscode.appLaunchers.displayNames = {
      python = "VSC - Python";
      web = "VSC - Web";
      writing = "VSC - Writing";
      native = "VSC - Default";
    };
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

      # Specify Nix CLI package for nix.conf generation
      nix.package = pkgs.nix;

      # Set primary user for homebrew
      system.primaryUser = userName;

      users.users.${userName} = {
        name = userName;
        home = homeDir;
      };
    };
}

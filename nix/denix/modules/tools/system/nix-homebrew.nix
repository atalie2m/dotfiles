{ delib, lib, ... }:

# nix-homebrew: install Homebrew declaratively for nix-darwin

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.system.nixHomebrew";

  options = with delib; moduleOptions {
    enable = boolOption false;
    autoMigrate = boolOption true;
  };

  myconfig = {
    always = mkEnableDefault "tools.system.nixHomebrew.enable";
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      userName = myconfig.facts.user.username or myconfig.constants.username or "";
      platform = myconfig.facts.user.platform or myconfig.constants.platform;
      enableRosetta = platform == "aarch64-darwin";
    in
    {
      nix-homebrew = {
        enable = true;
        user = userName;
        inherit enableRosetta;
        autoMigrate = cfg.autoMigrate;
      };
    };
}

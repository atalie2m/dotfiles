{ delib, lib, pkgs, ... }:

# nix-homebrew: install Homebrew declaratively for nix-darwin

delib.module {
  name = "tools.system.nixHomebrew";

  options = with delib; moduleOptions {
    enable = boolOption false;
    autoMigrate = boolOption true;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.system.nixHomebrew.enable = lib.mkDefault parent.enable;
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      userName = myconfig.facts.user.username or myconfig.constants.username or "";
      platform = myconfig.facts.user.platform or pkgs.stdenv.hostPlatform.system;
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

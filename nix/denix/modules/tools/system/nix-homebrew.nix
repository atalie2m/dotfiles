{ delib, dotlib, inputs, ... }:

# nix-homebrew: install Homebrew declaratively for nix-darwin

delib.module {
  name = "tools.system.nixHomebrew";

  options = with delib; moduleOptions {
    enable = boolOption false;
    autoMigrate = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.system.nixHomebrew.enable";
  };

  darwin.always = { ... }: {
    imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];
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

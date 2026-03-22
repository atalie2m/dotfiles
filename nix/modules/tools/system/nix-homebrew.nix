{ delib, inputs, ... }:

# nix-homebrew: install Homebrew declaratively for nix-darwin

delib.module {
  name = "tools.system.nixHomebrew";

  options = with delib; moduleOptions {
    enable = boolOption false;
    autoMigrate = boolOption true;
  };

  darwin.always = { ... }: {
    imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];
  };

  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      userName = myconfig.hostContext.user.username;
      enableRosetta = myconfig.hostContext.system == "aarch64-darwin";
    in
    {
      nix-homebrew = {
        enable = true;
        user = userName;
        inherit enableRosetta;
        autoMigrate = cfg.autoMigrate;
        taps = {
          "d12frosted/homebrew-emacs-plus" = inputs.homebrew-emacs-plus;
        };
      };
    };
}

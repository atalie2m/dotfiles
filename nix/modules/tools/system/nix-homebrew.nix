{ dotmod, config, inputs, ... }:

# nix-homebrew: install Homebrew declaratively for nix-darwin

(dotmod.mkModule { inherit config; }) {
  path = "tools.system.nixHomebrew";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    autoMigrate = boolOption false;
  };

  darwinAlways = { ... }: {
    imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];
  };

  darwinOnEnable = { cfg, myconfig, ... }:
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

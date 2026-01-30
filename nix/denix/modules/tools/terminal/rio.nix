{ delib, lib, ... }:

# Rio terminal configuration

delib.module {
  name = "tools.terminal.rio";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.terminal.rio.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    programs.rio = {
      enable = true;
      settings = {
        fonts = {
          family = "0xProto Nerd Font";
          size = 11;
        };

        window = {
          opacity = 0.8;
        };
      };
    };
  };
}

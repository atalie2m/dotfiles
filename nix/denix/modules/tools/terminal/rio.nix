{ delib, lib, pkgs, ... }:

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

  home.ifEnabled = { ... }: let
    rioSettings = {
      fonts = {
        family = "0xProto Nerd Font";
        size = 11;
      };

      window = {
        opacity = 0.8;
      };
    };
    tomlFormat = pkgs.formats.toml { };
  in {
    # Rio app itself is installed via brew-nix; this module only manages config.
    xdg.configFile = {
      "rio/config.toml".source = tomlFormat.generate "rio.toml" rioSettings;
    };
  };
}

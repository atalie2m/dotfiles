{ delib, pkgs, ... }:

# Fonts configuration shared across platforms

delib.module {
  name = "fonts";

  options.fonts = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = { cfg, ... }: {
    fonts.fontconfig.enable = true;
  };

  darwin.ifEnabled = { cfg, ... }: {
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts._0xproto
      roboto
      roboto-mono
    ];
  };
}

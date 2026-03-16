{ delib, pkgs, ... }:

delib.module {
  name = "tools.system.fonts";

  options = with delib; moduleOptions {
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

{ dotmod, config, pkgs, ... }:

(dotmod.mkModule { inherit config; }) {
  path = "tools.system.fonts";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { cfg, ... }: {
    fonts.fontconfig.enable = true;
  };

  darwinOnEnable = { cfg, ... }: {
    fonts.packages = with pkgs; [
      nerd-fonts.jetbrains-mono
      nerd-fonts._0xproto
      roboto
      roboto-mono
    ];
  };
}

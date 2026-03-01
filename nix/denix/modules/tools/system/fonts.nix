{ delib, lib, pkgs, ... }:

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.system.fonts";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.system.fonts.enable";
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

{ delib, lib, ... }:

# Starship prompt configuration

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.shell.starship";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.shell.starship.enable";
  };

  home.ifEnabled = { myconfig, ... }: {
    programs.starship = {
      enable = true;
      enableZshIntegration = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
      enableBashIntegration = (((myconfig.tools or { }).shell or { }).bash or { }).enable or false;
    };

    xdg.configFile."starship.toml" = {
      force = true;
      source = ../../../../../apps/starship.toml;
    };
  };
}

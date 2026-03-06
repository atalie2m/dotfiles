{ delib, lib, dotlib, ... }:

# Starship prompt configuration

delib.module {
  name = "tools.shell.starship";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.starship.enable";
  };

  home.ifEnabled = { myconfig, ... }: {
    programs.starship = {
      enable = true;
      enableZshIntegration = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
      enableBashIntegration = (((myconfig.tools or { }).shell or { }).bash or { }).enable or false;
      enableFishIntegration = (((myconfig.tools or { }).shell or { }).fish or { }).enable or false;
    };

    xdg.configFile."starship.toml" = {
      force = true;
      source = ../../../../../apps/starship.toml;
    };
  };
}

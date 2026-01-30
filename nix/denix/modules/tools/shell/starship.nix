{ delib, lib, pkgs, config, ... }:

# Starship prompt configuration

delib.module {
  name = "tools.shell.starship";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.shell.starship.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { ... }: {
    programs.starship = {
      enable = true;
      enableZshIntegration = config.tools.shell.zsh.enable or false;
      # Bash integration handled manually in ~/.nix/.bashrc
      enableBashIntegration = false;
    };

    xdg.configFile."starship.toml" = {
      source = ../../../../../apps/starship.toml;
    };
  };
}

{ delib, lib, pkgs, ... }:

# fzf-tab completion selector

delib.module {
  name = "tools.shell.fzfTab";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
      zshProfile = (((myconfig.tools or { }).shell or { }).zsh or { }).profile or "stable";
    in
    lib.mkIf (zshEnabled && zshProfile != "autocomplete") {
      programs.zsh.initContent = lib.mkOrder 920 ''
        source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh
      '';
    };
}

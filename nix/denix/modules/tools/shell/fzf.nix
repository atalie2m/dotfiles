{ delib, lib, pkgs, ... }:

# fzf keybinding setup without replacing Tab completion.

delib.module {
  name = "tools.shell.fzf";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
    in
    lib.mkIf zshEnabled {
      programs.fzf = {
        enable = true;
        enableBashIntegration = false;
        enableFishIntegration = false;
        enableZshIntegration = false;
      };

      programs.zsh.initContent = lib.mkOrder 910 ''
        if [[ $options[zle] = on ]]; then
          source ${pkgs.fzf}/share/fzf/key-bindings.zsh
        fi
      '';
    };
}

{ delib, lib, pkgs, ... }:

# Atuin history integration

delib.module {
  name = "tools.shell.atuin";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
      atuinFlags = "--disable-up-arrow";
    in
    lib.mkIf zshEnabled {
      programs.atuin = {
        enable = true;
        enableBashIntegration = false;
        enableFishIntegration = false;
        enableNushellIntegration = false;
        enableZshIntegration = false;
        flags = [ atuinFlags ];
      };

      programs.zsh.initContent = lib.mkOrder 1090 ''
        if [[ $options[zle] = on ]]; then
          eval "$(${lib.getExe pkgs.atuin} init zsh ${atuinFlags})"
        fi
      '';
    };
}

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
        # Atuin rewrites config.toml after commands; HM must own the file or activation conflicts.
        forceOverwriteSettings = true;
        # Prefer cwd-scoped history in the Atuin UI (Ctrl+R). ↑ stays zsh native (--disable-up-arrow).
        settings = {
          filter_mode = "directory";
          search.filters = [
            "directory"
            "global"
            "host"
            "session"
            "session-preload"
            "workspace"
          ];
        };
      };

      programs.zsh.initContent = lib.mkOrder 1090 ''
        if [[ $options[zle] = on ]]; then
          eval "$(${lib.getExe pkgs.atuin} init zsh ${atuinFlags})"
        fi
      '';
    };
}

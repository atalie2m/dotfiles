{ dotmod, config, lib, pkgs, ... }:

# Atuin history integration

(dotmod.mkModule { inherit config; }) {
  path = "tools.shell.atuin";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
      atuinFlags = [ ];
      atuinInitArgs = lib.optionalString (atuinFlags != [ ]) (" " + lib.concatStringsSep " " atuinFlags);
    in
    lib.mkIf zshEnabled {
      programs.atuin = {
        enable = true;
        enableBashIntegration = false;
        enableFishIntegration = false;
        enableNushellIntegration = false;
        enableZshIntegration = false;
        flags = atuinFlags;
        # Atuin rewrites config.toml after commands; HM must own the file or activation conflicts.
        forceOverwriteSettings = true;
        # Let Atuin own history navigation and autosuggestions. Bias searches
        # toward the current workspace, with directory/global fallbacks.
        settings = {
          workspaces = true;
          filter_mode = "workspace";
          filter_mode_shell_up_key_binding = "workspace";
          search_mode_shell_up_key_binding = "prefix";
          search.filters = [
            "workspace"
            "directory"
            "global"
            "host"
            "session"
            "session-preload"
          ];
        };
      };

      programs.zsh.initContent = lib.mkOrder 1090 ''
        if [[ $options[zle] = on ]]; then
          export PATH="${lib.makeBinPath [ pkgs.atuin ]}:$PATH"
          eval "$(${lib.getExe pkgs.atuin} init zsh${atuinInitArgs})"
        fi
      '';
    };
}

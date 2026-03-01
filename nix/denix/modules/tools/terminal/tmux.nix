{ delib, lib, ... }:

# Tmux configuration
delib.module {
  name = "tools.terminal.tmux";

  options = with delib; moduleOptions {
    enable = boolOption false;
    utf8Locale = strOption "en_US.UTF-8";
    extraConfig = strOption "";
  };

  myconfig = {
    always = { parent, ... }: {
      tools.terminal.tmux.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, ... }: {
    programs.tmux = {
      enable = true;
      extraConfig = ''
        # Ensure UTF-8 locale in tmux sessions.
        set -g update-environment "LANG LC_ALL LC_CTYPE"
        set-environment -g LANG "${cfg.utf8Locale}"
        set-environment -g LC_ALL "${cfg.utf8Locale}"
        set-environment -g LC_CTYPE "${cfg.utf8Locale}"

        ${cfg.extraConfig}
      '';
    };
  };
}

{ delib, lib, ... }:

# Bash configuration

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.shell.bash";

  options = with delib; moduleOptions {
    enable = boolOption false;
    enableCompletion = boolOption true;
    historySize = intOption 10000;
  };

  myconfig = {
    always = mkEnableDefault "tools.shell.bash.enable";
  };

  home.ifEnabled = { cfg, ... }: {
    programs.bash = {
      enable = true;
      inherit (cfg) enableCompletion;

      shellAliases = {
        helloworld = "echo '👋 Hello from Bash! You are running in a Bash shell.'";
      };

      initExtra = ''
        HISTCONTROL=ignoredups:ignorespace
        HISTSIZE=${toString cfg.historySize}
        HISTFILESIZE=$(( ${toString cfg.historySize} * 2 ))

        if [[ -f "$HOME/.config/shell/common.sh" ]]; then
          source "$HOME/.config/shell/common.sh"
        fi

        if [[ -f "$HOME/.bashrc.local" ]]; then
          source "$HOME/.bashrc.local"
        fi
      '';
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    programs.bash.enable = lib.mkForce (
      (((myconfig.tools or { }).shell or { }).manageSystemShells or false) && cfg.enable
    );
  };
}

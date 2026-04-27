{ dotmod, config, lib, ... }:

# Bash configuration

(dotmod.mkModule { inherit config; }) {
  path = "tools.shell.bash";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    enableCompletion = boolOption true;
    historySize = intOption 10000;
  };

  homeOnEnable = { cfg, ... }: {
    programs.bash = {
      enable = true;
      inherit (cfg) enableCompletion;

      initExtra = ''
        HISTCONTROL=ignoredups:ignorespace
        HISTSIZE=${toString cfg.historySize}
        HISTFILESIZE=$(( ${toString cfg.historySize} * 2 ))

        if [[ -f "$HOME/.config/shell/common.sh" ]]; then
          source "$HOME/.config/shell/common.sh"
        fi
      '';
    };

    # Keep Home Manager generated bashrc in a separate immutable layer.
    # The runtime ~/.bashrc entrypoint is managed as a writable wrapper.
    home.file.".bashrc".target = lib.mkForce ".nix/hm-bash/.bashrc";
  };

  darwinOnEnable = { cfg, myconfig, ... }: {
    programs.bash.enable = lib.mkForce (
      (((myconfig.tools or { }).shell or { }).manageSystemShells or false) && cfg.enable
    );
  };
}

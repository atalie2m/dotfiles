{ delib, lib, pkgs, ... }:

# Zsh configuration

delib.module {
  name = "tools.shell.zsh";

  options = with delib; moduleOptions {
    enable = boolOption false;
    enableAutosuggestions = boolOption true;
    enableSyntaxHighlighting = boolOption true;
    enableCompletion = boolOption true;
    historySize = intOption 10000;
  };

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      homeDir = myconfig.hostContext.user.homeDirectory;
    in
    {
      programs.zsh = {
        enable = true;
        dotDir = "${homeDir}/.nix/hm-zsh";

        envExtra = ''
          export ZDOTDIR="$HOME/.nix"
        '';

        history = {
          size = cfg.historySize;
          save = cfg.historySize;
          ignoreDups = true;
          ignoreSpace = true;
        };

        initContent = lib.mkMerge [
          (lib.mkOrder 500 ''
            if [[ -f "$HOME/.config/shell/common.sh" ]]; then
              source "$HOME/.config/shell/common.sh"
            fi

            # Avoid right-prompt artifacts on resize and when typing.
            setopt TRANSIENT_RPROMPT
            setopt PROMPT_CR
            setopt PROMPT_SP
            ZLE_RPROMPT_INDENT=1
            PROMPT_EOL_MARK=""
            TRAPWINCH() { zle && zle -R }
          '')
          (lib.mkIf cfg.enableAutosuggestions (lib.mkOrder 1100 ''
            source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
          ''))
          (lib.mkOrder 1150 ''
            if [[ -f "$HOME/.config/shell/zsh.local.sh" ]]; then
              source "$HOME/.config/shell/zsh.local.sh"
            fi
          '')
          (lib.mkIf cfg.enableSyntaxHighlighting (lib.mkOrder 1200 ''
            # Keep syntax highlighting last so late widgets are visible to it.
            source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
          ''))
        ];

        inherit (cfg) enableCompletion;
      };
    };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    programs.zsh.enable = lib.mkForce (
      (((myconfig.tools or { }).shell or { }).manageSystemShells or false) && cfg.enable
    );
  };
}

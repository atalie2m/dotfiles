{ delib, lib, dotlib, ... }:

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

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.zsh.enable";
  };

  home.ifEnabled = { cfg, ... }: {
    programs.zsh = {
      enable = true;
      dotDir = ".nix";

      history = {
        size = cfg.historySize;
        save = cfg.historySize;
        ignoreDups = true;
        ignoreSpace = true;
      };

      shellAliases = {
        helloworld = "echo '👋 Hello from Zsh! You are running in a Zsh shell.'";
      };

      initContent = ''
        if [[ -f "$HOME/.config/shell/common.sh" ]]; then
          source "$HOME/.config/shell/common.sh"
        fi

        # Avoid right-prompt artifacts on resize and when typing
        # - transient_rprompt hides RPROMPT while typing
        # - prompt_cr/prompt_sp improve redraw on wraps and partial lines
        setopt TRANSIENT_RPROMPT
        setopt PROMPT_CR
        setopt PROMPT_SP
        # keep a small gap from terminal edge to avoid wrap glitches
        ZLE_RPROMPT_INDENT=1
        # clear end-of-line mark to prevent leftovers on reflow
        PROMPT_EOL_MARK=""
        # full refresh on terminal resize
        TRAPWINCH() { zle && zle -R }

        # Load user-specific Zsh customizations if present
        if [[ -f "$HOME/.zshrc.local" ]]; then
          source "$HOME/.zshrc.local"
        fi
      '';

      autosuggestion.enable = cfg.enableAutosuggestions;
      syntaxHighlighting.enable = cfg.enableSyntaxHighlighting;
      inherit (cfg) enableCompletion;
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    programs.zsh.enable = lib.mkForce (
      (((myconfig.tools or { }).shell or { }).manageSystemShells or false) && cfg.enable
    );
  };
}

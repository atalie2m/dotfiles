{ dotmod, config, lib, pkgs, ... }:

# Pure prompt configuration

(dotmod.mkModule { inherit config; }) {
  path = "tools.shell.pure";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
    in
    lib.mkIf zshEnabled {
      home.packages = [ pkgs.pure-prompt ];

      programs.zsh.initContent = lib.mkOrder 1000 ''
        fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
        autoload -Uz promptinit
        : ''${PURE_CMD_MAX_EXEC_TIME:=2}
        export PURE_CMD_MAX_EXEC_TIME
        if [[ -n "$IN_NIX_SHELL" || -n "$NIX_SHELL" || -n "$NIX_SHELL_NAME" ]]; then
          typeset pure_prompt_symbol="❯"
          if [[ -n "$PURE_PROMPT_SYMBOL" ]]; then
            pure_prompt_symbol="$PURE_PROMPT_SYMBOL"
          fi
          if [[ $pure_prompt_symbol != "❄ "* ]]; then
            export PURE_PROMPT_SYMBOL="❄ $pure_prompt_symbol"
          fi
        fi
        promptinit
        prompt pure
        if [[ -n ''${DOTFILES_MOSH_SESSION:-} ]] && (( ''${+prompt_pure_state} )); then
          prompt_pure_state[username]=""
        fi
      '';
    };
}

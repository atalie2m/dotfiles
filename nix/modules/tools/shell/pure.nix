{ delib, lib, pkgs, dotlib, ... }:

# Pure prompt configuration

delib.module {
  name = "tools.shell.pure";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.shell.pure.enable";
  };

  home.ifEnabled = { myconfig, ... }:
    let
      zshEnabled = (((myconfig.tools or { }).shell or { }).zsh or { }).enable or false;
    in
    lib.mkIf zshEnabled {
      home.packages = [ pkgs.pure-prompt ];

      programs.zsh.initContent = lib.mkOrder 1000 ''
        fpath+=(${pkgs.pure-prompt}/share/zsh/site-functions)
        autoload -Uz promptinit
        if [[ -n ${IN_NIX_SHELL:-} || -n ${NIX_SHELL:-} || -n ${NIX_SHELL_NAME:-} ]]; then
          typeset pure_prompt_symbol="${PURE_PROMPT_SYMBOL:-❯}"
          if [[ $pure_prompt_symbol != "❄ "* ]]; then
            export PURE_PROMPT_SYMBOL="❄ ${pure_prompt_symbol}"
          fi
        fi
        promptinit
        prompt pure
      '';
    };
}

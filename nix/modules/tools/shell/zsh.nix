{ delib, lib, dotlib, pkgs, ... }:

# Zsh configuration

delib.module {
  name = "tools.shell.zsh";

  options = with delib; moduleOptions {
    enable = boolOption false;
    enableAutosuggestions = boolOption true;
    enableSyntaxHighlighting = boolOption true;
    enableCompletion = boolOption true;
    profile = strOption "stable";
    historySize = intOption 10000;
  };

  myconfig.ifEnabled = { ... }:
    dotlib.requireUnfree [ "zsh-abbr" ];

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      homeDir = myconfig.hostContext.user.homeDirectory;
      validProfiles = [ "stable" "autocomplete" "debug" ];
      useAutocomplete = cfg.profile == "autocomplete";
      useDebug = cfg.profile == "debug";
      useStablePlugins = cfg.profile == "stable" || cfg.profile == "debug";
    in
    {
      assertions = [
        {
          assertion = lib.elem cfg.profile validProfiles;
          message = "tools.shell.zsh.profile must be one of: stable, autocomplete, debug.";
        }
      ];

      home.packages =
        [
          pkgs.carapace
          pkgs.nix-zsh-completions
          pkgs.zsh-abbr
          pkgs.zinit
          pkgs.zsh-completions
          pkgs.zsh-defer
        ]
        ++ lib.optionals useStablePlugins [
          pkgs.zsh-autopair
          pkgs.zsh-fzf-history-search
          pkgs.zsh-fast-syntax-highlighting
          pkgs.zsh-history-substring-search
          pkgs.zsh-vi-mode
          pkgs.zsh-you-should-use
        ]
        ++ lib.optional useAutocomplete pkgs.zsh-autocomplete;

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
          (lib.mkIf useDebug (lib.mkOrder 100 ''
            zmodload zsh/zprof
          ''))
          (lib.mkOrder 500 ''
            if [[ -f "$HOME/.config/shell/common.sh" ]]; then
              source "$HOME/.config/shell/common.sh"
            fi

            fpath+=(${pkgs.zsh-completions}/share/zsh/site-functions)
            fpath+=(${pkgs.nix-zsh-completions}/share/zsh/site-functions)

            # Avoid right-prompt artifacts on resize and when typing.
            setopt TRANSIENT_RPROMPT
            setopt PROMPT_CR
            setopt PROMPT_SP
            ZLE_RPROMPT_INDENT=1
            PROMPT_EOL_MARK=""
            TRAPWINCH() { zle && zle -R }
          '')
          (lib.mkIf useStablePlugins (lib.mkOrder 905 ''
            source ${pkgs.zsh-defer}/share/zsh-defer/zsh-defer.plugin.zsh
            source ${pkgs.zsh-autopair}/share/zsh/zsh-autopair/autopair.zsh
            source ${pkgs.zsh-vi-mode}/share/zsh-vi-mode/zsh-vi-mode.plugin.zsh
            source ${pkgs.zsh-history-substring-search}/share/zsh/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh
            source ${pkgs.zsh-fzf-history-search}/share/zsh-fzf-history-search/zsh-fzf-history-search.plugin.zsh
            source ${pkgs.zsh-you-should-use}/share/zsh/plugins/you-should-use/you-should-use.plugin.zsh
            source ${pkgs.zsh-abbr}/share/zsh/zsh-abbr/zsh-abbr.plugin.zsh
            bindkey '^[[A' history-substring-search-up
            bindkey '^[[B' history-substring-search-down
          ''))
          (lib.mkOrder 906 ''
            if command -v carapace >/dev/null 2>&1; then
              export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
              source <(carapace _carapace)
            fi
          '')
          (lib.mkIf useAutocomplete (lib.mkOrder 907 ''
            source ${pkgs.zsh-autocomplete}/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
          ''))
          (lib.mkIf (cfg.enableAutosuggestions && useStablePlugins) (lib.mkOrder 1100 ''
            source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
          ''))
          (lib.mkOrder 1150 ''
            if [[ -f "$HOME/.config/shell/zsh.local.sh" ]]; then
              source "$HOME/.config/shell/zsh.local.sh"
            fi
          '')
          (lib.mkIf cfg.enableSyntaxHighlighting (lib.mkOrder 1200 ''
            # Keep syntax highlighting last so late widgets are visible to it.
            source ${pkgs.zsh-fast-syntax-highlighting}/share/zsh/plugins/fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh
          ''))
          (lib.mkIf useDebug (lib.mkOrder 1300 ''
            source ${pkgs.zinit}/share/zinit/zinit.zsh
            print -P "%F{cyan}zsh debug: bindkey map%f"
            bindkey
            print -P "%F{cyan}zsh debug: zinit report%f"
            zinit times || true
            zinit report || true
            zprof
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

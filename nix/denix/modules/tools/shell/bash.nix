{ delib, lib, pkgs, config, ... }:

# Bash configuration

delib.module {
  name = "tools.shell.bash";

  options = with delib; moduleOptions {
    enable = boolOption false;
    enableCompletion = boolOption true;
    historySize = intOption 10000;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.shell.bash.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    shellCfg = (myconfig.tools or {}).shell or {};

    commonAliases = {
      # File and directory operations
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";

      # Development aliases
      dev = "nix develop";
      build = "nix build";
      run = "nix run";
      search = "nix search";

      # Git shortcuts
      gs = "git status";
      ga = "git add";
      gc = "git commit";
      gp = "git push";
      gl = "git log --oneline";
    };

    commonShellInit = ''
      # Prefer GNU coreutils (unprefixed) when available
      if [ -d "${pkgs.coreutils}/libexec/gnubin" ]; then
        PATH="${pkgs.coreutils}/libexec/gnubin:$PATH"
        export PATH
      fi

      # Custom function for process search
      psgrep() {
        if [[ -z "''${1:-}" ]]; then
          echo "Usage: psgrep <pattern>" >&2
          return 1
        fi
        if command -v rg >/dev/null 2>&1; then
          ps aux | rg -i -- "$1"
        else
          ps aux | grep -i -- "$1" | grep -v "[g]rep"
        fi
      }

      # Show nix develop environment info (interactive shells only)
      if [[ $- == *i* ]] && [[ -n "''${IN_NIX_SHELL:-}" ]]; then
        echo "🚀 Nix develop environment active"
        if [[ -n "''${DEVENV_PROFILE:-}" ]]; then
          echo "Environment: ''${DEVENV_PROFILE}"
        elif [[ -n "''${NIX_SHELL_NAME:-}" ]]; then
          echo "Environment: ''${NIX_SHELL_NAME}"
        fi
      fi
    '';

    allAliases = commonAliases // shellCfg.extraAliases;
  in {
    programs.bash = {
      enable = true;
      inherit (cfg) enableCompletion;

      # Source Nix-managed bashrc located under ~/.nix
      initExtra = ''
        if [[ -f "$HOME/.nix/.bashrc" ]]; then
          source "$HOME/.nix/.bashrc"
        fi
      '';
    };

    home.file.".nix/.bashrc" = {
      text = ''
        # History configuration
        HISTCONTROL=ignoredups:ignorespace
        HISTSIZE=${toString cfg.historySize}
        HISTFILESIZE=$(( ${toString cfg.historySize} * 2 ))

        # Common shell initialization
        ${commonShellInit}

        # Shell aliases (shared and Bash specific)
        ${lib.concatStringsSep "" (lib.mapAttrsToList (name: value: ''alias ${name}="${value}"\n'') allAliases)}
        alias helloworld="echo '👋 Hello from Bash! You are running in a Bash shell.'"

        # Initialize Starship prompt if available
        if command -v starship >/dev/null 2>&1; then
          eval "$(starship init bash)"
        fi

        # Load user-specific Bash customizations if present
        if [[ -f "$HOME/.bashrc.local" ]]; then
          source "$HOME/.bashrc.local"
        fi
      '';
    };
  };

  darwin.ifEnabled = { cfg, myconfig, ... }: {
    programs.bash.enable = lib.mkForce (
      (((myconfig.tools or {}).shell or {}).manageSystemShells or false) && cfg.enable
    );
  };
}

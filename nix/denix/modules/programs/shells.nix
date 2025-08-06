{ delib, lib, pkgs, ... }:

# Unified shell configuration for zsh, bash, and starship
delib.module {
  name = "shells";

  options.shells = with delib.options; {
    enable = boolOption false;
    
    zsh = {
      enable = boolOption false;
      enableAutosuggestions = boolOption true;
      enableSyntaxHighlighting = boolOption true;
      enableCompletion = boolOption true;
      historySize = intOption 10000;
    };
    
    bash = {
      enable = boolOption false;
      enableCompletion = boolOption true;
      historySize = intOption 10000;
    };
    
    starship = {
      enable = boolOption false;
    };
    
    defaultShell = strOption "zsh";
    extraAliases = attrsOption {};
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    # Common shell aliases
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

    # Common shell initialization
    commonShellInit = ''
      # Custom function for process search
      psgrep() {
        ps aux | grep -i "$1" | grep -v grep
      }

      # Show nix develop environment info
      if [[ -n "$IN_NIX_SHELL" ]]; then
        echo "🚀 Nix develop environment active"
        if [[ -n "$name" ]]; then
          echo "Environment: $name"
        fi
      fi
    '';
    
    allAliases = commonAliases // cfg.extraAliases;
  in {
    # Zsh configuration
    programs.zsh = lib.mkIf cfg.zsh.enable {
      enable = true;
      dotDir = ".nix";
      
      history = {
        size = cfg.zsh.historySize;
        save = cfg.zsh.historySize;
        ignoreDups = true;
        ignoreSpace = true;
      };
      
      shellAliases = allAliases // {
        # Zsh-specific alias
        helloworld = "echo '👋 Hello from Zsh! You are running in a Zsh shell.'";
      };
      
      initContent = ''
        ${commonShellInit}
        
        # Load local ~/.zshrc if it exists
        if [[ -f ~/.zshrc ]]; then
          source ~/.zshrc
        fi
      '';
      
      autosuggestion.enable = cfg.zsh.enableAutosuggestions;
      syntaxHighlighting.enable = cfg.zsh.enableSyntaxHighlighting;
      enableCompletion = cfg.zsh.enableCompletion;
    };

    # Bash configuration  
    programs.bash = lib.mkIf cfg.bash.enable {
      enable = true;
      
      historyControl = [ "ignoredups" "ignorespace" ];
      historySize = cfg.bash.historySize;
      historyFileSize = cfg.bash.historySize * 2;
      
      shellAliases = allAliases // {
        # Bash-specific alias
        helloworld = "echo '👋 Hello from Bash! You are running in a Bash shell.'";
      };
      
      initExtra = ''
        ${commonShellInit}
        
        # Load local ~/.bashrc if it exists
        if [[ -f ~/.bashrc ]]; then
          source ~/.bashrc
        fi
      '';
      
      enableCompletion = cfg.bash.enableCompletion;
    };

    # Starship prompt configuration
    programs.starship = lib.mkIf cfg.starship.enable {
      enable = true;
      enableZshIntegration = cfg.zsh.enable;
      enableBashIntegration = cfg.bash.enable;
      
      settings = lib.mkDefault {
        # Custom starship configuration
        format = "$all$character";
        
        character = {
          success_symbol = "[➜](bold green)";
          error_symbol = "[➜](bold red)";
        };
        
        git_branch = {
          format = "[$branch]($style)";
          style = "bright-black";
        };
        
        git_status = {
          format = "[[($all_status$ahead_behind )]($style)]";
          style = "cyan";
        };
        
        nix_shell = {
          disabled = false;
          impure_msg = "[impure shell](bold red)";
          pure_msg = "[pure shell](bold green)";
          unknown_msg = "[unknown shell](bold yellow)";
          format = "via [☃️ $state( \($name\))](bold blue) ";
        };
      };
    };

    # Session variables
    home.sessionVariables = lib.mkMerge [
      (lib.mkIf cfg.zsh.enable {
        ZDOTDIR = "$HOME/.nix";
      })
      # Let Home Manager handle SHELL variable automatically based on enabled shells
    ];
  };

  # Darwin-specific shell configuration
  darwin.ifEnabled = { cfg, ... }: {
    programs.zsh.enable = cfg.zsh.enable;
    programs.bash.enable = cfg.bash.enable;
  };
}
_: {
  programs.zsh = {
    enable = true;
    dotDir = ".nix";

    history = {
      size = 10000;
      save = 10000;
      ignoreDups = true;
      ignoreSpace = true;
    };

    shellAliases = {
      # file and directory operations
      ll = "ls -la";
      la = "ls -A";
      l = "ls -CF";
    };

    # Custom functions
    initContent = ''
      # Load local ~/.zshrc
      # This might break the benefits of Nix, but I rather fancy it.
      if [[ -f ~/.zshrc ]]; then
        source ~/.zshrc
      fi

      # search for processes by name
      psgrep() {
        ps aux | grep -i "$1" | grep -v grep
      }
    '';

    # auto-completion and syntax highlighting
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Starship prompt configuration
  programs.starship = {
    enable = true;
    # Tokyo Night preset - a beautiful powerline-style theme
    settings = {
      format =
        "[░▒▓](#a3aed2)" +
        "[  ](bg:#a3aed2 fg:#090c0c)" +
        "[](bg:#769ff0 fg:#a3aed2)" +
        "$directory" +
        "[](fg:#769ff0 bg:#394260)" +
        "$git_branch" +
        "$git_status" +
        "[](fg:#394260 bg:#212736)" +
        "$nodejs" +
        "$rust" +
        "$golang" +
        "$php" +
        "[](fg:#212736 bg:#1d2230)" +
        "$time" +
        "[ ](fg:#1d2230)" +
        "\n$character";

      directory = {
        style = "fg:#e3e5e5 bg:#769ff0";
        format = "[ $path ]($style)";
        truncation_length = 3;
        truncation_symbol = "…/";
        substitutions = {
          "Documents" = "󰈙 ";
          "Downloads" = " ";
          "Music" = " ";
          "Pictures" = " ";
        };
      };

      git_branch = {
        symbol = "";
        style = "bg:#394260";
        format = "[[ $symbol $branch ](fg:#769ff0 bg:#394260)]($style)";
      };

      git_status = {
        style = "bg:#394260";
        format = "[[($all_status$ahead_behind )](fg:#769ff0 bg:#394260)]($style)";
      };

      nodejs = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      rust = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      golang = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      php = {
        symbol = "";
        style = "bg:#212736";
        format = "[[ $symbol ($version) ](fg:#769ff0 bg:#212736)]($style)";
      };

      time = {
        disabled = false;
        time_format = "%R"; # Hour:Minute Format
        style = "bg:#1d2230";
        format = "[[  $time ](fg:#a0a9cb bg:#1d2230)]($style)";
      };
    };
  };

  home.sessionVariables = {
    ZDOTDIR = "$HOME/.nix";
  };
}

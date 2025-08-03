{ pkgs, ... }: {
  # Common shell aliases for both bash and zsh
  shellAliases = {
    # file and directory operations
    ll = "ls -la";
    la = "ls -A";
    l = "ls -CF";

    # development aliases
    dev = "nix develop";
    build = "nix build";
    run = "nix run";
    search = "nix search";

    # git shortcuts
    gs = "git status";
    ga = "git add";
    gc = "git commit";
    gp = "git push";
    gl = "git log --oneline";
  };

  # Common shell initialization for both bash and zsh
  commonShellInit = ''
    # Custom function for process search
    psgrep() {
      ps aux | grep -i "$1" | grep -v grep
    }

    # Initialize starship based on shell type
    if command -v starship >/dev/null 2>&1; then
      if [[ -n "$BASH_VERSION" ]]; then
        eval "$(starship init bash)"
      elif [[ -n "$ZSH_VERSION" ]]; then
        eval "$(starship init zsh)"
      fi
    fi

    # Show nix develop environment info (only in nix develop)
    if [[ -n "$IN_NIX_SHELL" ]]; then
      echo "🚀 Nix develop environment active"
      if [[ -n "$name" ]]; then
        echo "Environment: $name"
      fi
    fi
  '';
}

{ pkgs, ... }: {
  # Common shell configuration for both Bash and Zsh
  # Contains Bash-compatible syntax that can be shared

  # Common shell aliases
  shellAliases = {
    # file and directory operations
    ll = "ls -la";
    la = "ls -A";
    l = "ls -CF";
  };

  # Common functions (Bash-compatible syntax)
  commonInitContent = ''
    # search for processes by name
    psgrep() {
      ps aux | grep -i "$1" | grep -v grep
    }
  '';
}

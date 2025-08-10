{ delib, ... }:

# Full rice: Complete development and productivity environment
delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  myconfig = {
    # Override system overview for full profile
    system.overview = {
      enable = true;
      profile = "full";
      features = {
        developmentTools = true;
        productivitySuite = true;
        guiApplications = true;
        cloudSync = false;
      };
    };

    # Additional programs beyond minimum
    gpg.enable = true;
    karabiner.enable = true;

    # Smart backup service for managing configuration conflicts
    smartBackup = {
      enable = true;
      managedFiles = [
        "$HOME/.config/karabiner/karabiner.json"
        "$HOME/.vscode/extensions"
      ];
    };

    # VSCode default profile via denix module
    vscode.enable = true;

    # Allow VSCode (unfree) as an allowed package for nixpkgs.unfree
    nixpkgs.unfree.packages = [ "claude-code" "vscode" ];

    # Unified shell configuration
    shells = {
      enable = true;
      zsh.enable = true;
      bash.enable = true;
      starship.enable = true;
      defaultShell = "zsh";
    };

    # Enhanced package sets
    packages = {
      core.enable = true;
      development.enable = true;
      productivity.enable = true;
      claude-code-overlay.enable = true;  # Enable claude-code overlay
      codex-overlay.enable = true;  # Enable codex overlay
    };

    # Native homebrew integration
    homebrew.native.enable = true;

    # Brew-nix integration for GUI applications
    brew-nix.enable = true;
  };
}

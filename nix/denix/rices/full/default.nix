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
    # Install sops/age CLIs and enable sops-nix integration when secrets are provided
    sops.enable = true;

    # Smart backup service for managing configuration conflicts
    smartBackup = {
      enable = true;
      managedFiles = [
        "$HOME/.config/karabiner/karabiner.json"
      ];
    };

    # Unified shell configuration
    shells = {
      enable = true;
      zsh.enable = true;
      bash.enable = true;
      starship.enable = true;
      defaultShell = "zsh";
    };

    vscode.enable = true;

    # Tool catalog defaults
    tools.aiCodingAgent.enable = true;

    # Enhanced package sets
    packages = {
      core.enable = true;
      development.enable = true;
      productivity.enable = true;
    };

    # Native homebrew integration
    homebrew.native.enable = true;

    # Brew-nix integration for GUI applications
    brew-nix = {
      enable = true;
      appLinks.enable = true;
      autoTrampolines.enable = false;
    };
  };
}

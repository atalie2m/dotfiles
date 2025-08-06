{ delib, ... }:

# Minimum rice: Essential tools and configuration for basic system operation
delib.rice {
  name = "minimum";

  myconfig = {
    # System overview configuration
    system.overview = {
      enable = true;
      profile = "minimal";
      features = {
        developmentTools = false;
        productivitySuite = false;
        guiApplications = false;
        cloudSync = false;
      };
    };

    # Essential system configuration
    nixpkgs.unfree.enable = true;
    terminal.enable = true;
    fonts.enable = true;
    smartBackup.enable = true;

    # Enable modern Nix features
    system.nix.enable = true;

    # Core tools
    git.enable = true;

    # Essential packages only
    packages = {
      core.enable = true;
    };
  };
}

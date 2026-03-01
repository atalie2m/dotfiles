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
    nixpkgs.unfree = {
      enable = true;
      # Keep unfree permissions explicit and minimal for predictable ops.
      allowAll = false;
      packages = [
        "terraform"
        "vscode"
      ];
    };
    tools.core.enable = true;
    tools.security.enable = true;
    tools.dev.git.enable = true;
    tools.terminal.rio.enable = true;
    tools.terminal.terminalApp.enable = true;
    tools.system.fonts.enable = true;
    tools.system.hostnames.enable = true;
    # Enable modern Nix features
    system.nix.enable = true;

    # Core tools
    # Git/GPG/Sops now managed via tools.*
  };
}

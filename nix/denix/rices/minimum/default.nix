{ delib, ... }:

delib.rice {
  name = "minimum";

  myconfig = {
    nixpkgs.unfree.enable = true;
    terminal.enable = true;
    fonts.enable = true;
    smartBackup.enable = true;
    git.enable = true;
    
    # Categorized packages
    packages = {
      core.enable = true;
      development.enable = true;
      productivity.enable = true;
    };
  };
}

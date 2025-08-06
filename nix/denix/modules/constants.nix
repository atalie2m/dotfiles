{ delib, ... }:

let
  env = import ../../env.nix;
in
# Global constants and user information shared across all modules
delib.module {
  name = "constants";

  options.constants = with delib.options; {
    # User identification
    username = readOnly (strOption env.username);
    fullName = readOnly (strOption env.fullName);
    email = readOnly (strOption env.email);
    
    # System paths
    homeDirectory = readOnly (strOption env.homeDirectory);
    configDirectory = readOnly (strOption env.configDirectory);
    
    # Repository information
    dotfilesPath = readOnly (strOption env.dotfilesPath);
    
    # System information
    systemType = readOnly (strOption env.systemType);
    architecture = readOnly (strOption env.architecture);
  };
}
{ delib, config, ... }:

let
  user = config.facts.user or {};
in
# Global constants and user information shared across all modules
delib.module {
  name = "constants";

  options.constants = with delib.options; {
    # User identification
    username = readOnly (strOption (user.username or ""));
    fullName = readOnly (strOption (user.fullName or ""));
    email = readOnly (strOption (user.email or ""));
    
    # System paths
    homeDirectory = readOnly (strOption (user.homeDirectory or ""));
    configDirectory = readOnly (strOption (user.configDirectory or ".config"));
    
    # Repository information
    dotfilesPath = readOnly (strOption (user.dotfilesPath or ""));
    
    # System information
    systemType = readOnly (strOption (user.systemType or ""));
    architecture = readOnly (strOption (user.architecture or ""));
  };
}

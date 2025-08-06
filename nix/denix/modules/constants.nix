{ delib, ... }:

# Global constants and user information shared across all modules
delib.module {
  name = "constants";

  options.constants = with delib.options; {
    # User identification
    username = readOnly (strOption "{{USER_NAME}}");
    fullName = readOnly (strOption "Atalie User");
    email = readOnly (strOption "user@example.com");
    
    # System paths
    homeDirectory = readOnly (strOption "/Users/{{USER_NAME}}");
    configDirectory = readOnly (strOption ".config");
    
    # Repository information
    dotfilesPath = readOnly (strOption "/Users/{{USER_NAME}}/Local/atalie2m/GitHub/dotfiles");
  };
}
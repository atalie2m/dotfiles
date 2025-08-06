{
  # Environment variable equivalents - centralized user/system information

  # User information
  username = "{{USER_NAME}}";
  fullName = "Atalie";
  email = "user@example.com";

  # System information
  architecture = "aarch64";
  systemType = "darwin";

  # Paths
  homeDirectory = "/Users/{{USER_NAME}}";
  configDirectory = ".config";
  dotfilesPath = "/Users/{{USER_NAME}}/Local/atalie2m/GitHub/dotfiles";

  # State versions
  stateVersion = {
    home = "25.05";
    darwin = 6;
  };

  # Derived values
  platform = "aarch64-darwin";
}

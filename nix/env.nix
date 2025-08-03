{
  hosts = {
    standard = {
      system = "aarch64-darwin";
      username = "{{USER_NAME}}";
      profile = "standard";
    };
    commercial = {
      system = "aarch64-darwin";
      username = "{{USER_NAME}}";
      profile = "commercial";
    };
  };

  defaults = {
    stateVersion = {
      home = "25.05";
      darwin = 6;
    };
    homeDirectory = username: "/Users/${username}";
    dotfilesPath = "/Users/{{USER_NAME}}/Local/atalie2m/GitHub/dotfiles";
  };
}

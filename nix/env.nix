{
  hosts = {
    "{{LOCAL_HOSTNAME}}" = {
      system = "aarch64-darwin";
      username = "{{USER_NAME}}";
    };
  };

  defaults = {
    stateVersion = {
      home = "25.05";
      darwin = 6;
    };
    homeDirectory = username: "/Users/${username}";
  };
}

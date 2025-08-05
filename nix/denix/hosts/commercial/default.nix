{ delib, ... }:

delib.host {
  name = "commercial";
  rice = "minimum";
  type = "desktop";
  homeManagerSystem = "aarch64-darwin";

  home = { name, cfg, myconfig, ... }: {
    home.stateVersion = "25.05";
    # Note: Removing claude-code package would need to be handled differently in denix
  };

  darwin = { name, cfg, myconfig, ... }: {
    system.stateVersion = 5;
    nixpkgs.hostPlatform = "aarch64-darwin";
    
    users.users.u1 = {
      name = "{{USER_NAME}}";
      home = "/Users/{{USER_NAME}}";
    };
  };
}

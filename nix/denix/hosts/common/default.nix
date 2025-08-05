{ delib, ... }:

delib.host {
  name = "common";
  rice = "full";
  type = "desktop";
  homeManagerSystem = "aarch64-darwin";

  home = { name, cfg, myconfig, ... }: {
    home.stateVersion = "25.05";
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

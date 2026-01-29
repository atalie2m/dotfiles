{ delib, inputs, ... }:

# mac-app-util integration for Spotlight/Dock trampolines
# https://github.com/hraban/mac-app-util

delib.module {
  name = "mac-app-util";

  options.mac-app-util = with delib.options; {
    enable = boolOption false;
  };

  darwin.ifEnabled = { ... }: {
    services.mac-app-util.enable = true;
    home-manager.sharedModules = [ inputs.mac-app-util.homeManagerModules.default ];
  };

  home.ifEnabled = { ... }: {
    targets.darwin.mac-app-util.enable = true;
  };
}

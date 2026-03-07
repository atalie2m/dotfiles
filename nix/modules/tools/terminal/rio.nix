{ delib, lib, dotlib, pkgs, repoPaths, ... }:

let
  dedicatedHomebrewCatalog = import (repoPaths.catalog + "/tools/homebrew-dedicated.nix");
  homebrewSpec = dedicatedHomebrewCatalog."terminal.rio";
in

# Rio terminal configuration

delib.module {
  name = "tools.terminal.rio";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.terminal.rio.enable";
    ifEnabled = { myconfig, ... }:
      dotlib.ifDarwin myconfig (dotlib.requireHomebrew {
        taps = homebrewSpec.taps or [ ];
        brews = homebrewSpec.brews or [ ];
        casks = homebrewSpec.casks or [ ];
        masApps = homebrewSpec.masApps or { };
      });
  };

  home.ifEnabled = { ... }:
    let
      rioSettings = {
        fonts = {
          family = "0xProto Nerd Font";
          size = 11;
        };

        window = {
          opacity = 0.8;
        };
      };
      tomlFormat = pkgs.formats.toml { };
    in
    {
      xdg.configFile = {
        "rio/config.toml" = {
          force = true;
          source = tomlFormat.generate "rio.toml" rioSettings;
        };
      };
    };
}

{ delib, dotlib, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."terminal.wezterm";
in

# WezTerm terminal configuration

delib.module {
  name = "tools.terminal.wezterm";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig.ifEnabled = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  home.ifEnabled = { ... }:
    {
      xdg.configFile."wezterm/wezterm.lua" = {
        force = true;
        source = repoPaths.apps + "/wezterm/wezterm.lua";
      };
    };
}

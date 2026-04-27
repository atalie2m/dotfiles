{ dotmod, config, dotlib, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."terminal.wezterm";
in

# WezTerm terminal configuration

(dotmod.mkModule { inherit config; }) {
  path = "tools.terminal.wezterm";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  myconfigOnEnable = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  homeOnEnable = { ... }:
    {
      xdg.configFile."wezterm/wezterm.lua" = {
        force = true;
        source = repoPaths.apps + "/wezterm/wezterm.lua";
      };
    };
}

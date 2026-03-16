{ delib, lib, dotlib, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."terminal.rio";
in

# Rio terminal configuration

delib.module {
  name = "tools.terminal.rio";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig.ifEnabled = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  home.ifEnabled = { myconfig, ... }:
    let
      tmuxEnabled = (((myconfig.tools or { }).terminal or { }).tmux or { }).enable or false;
      navigationMode = if tmuxEnabled then "Plain" else "Bookmark";
      optionAsAltLine = lib.optionalString pkgs.stdenv.isDarwin ''
        option-as-alt = "left"
      '';
      platformBlock = lib.optionalString (pkgs.stdenv.isDarwin && !tmuxEnabled) ''
        [platform]
        macos.navigation.mode = "NativeTab"
      '';
      colorAutomationBlock = lib.optionalString (!tmuxEnabled) ''
        color-automation = [
          { program = "nvim", color = "#7aa2f7" },
          { program = "ssh", color = "#e0af68" },
        ]
      '';
      rioConfigTemplate = builtins.readFile (repoPaths.apps + "/rio/config.toml.template");
      rioConfig = pkgs.writeText "rio-config.toml" (
        lib.replaceStrings
          [
            "@@OPTION_AS_ALT@@"
            "@@NAVIGATION_MODE@@"
            "@@COLOR_AUTOMATION_BLOCK@@"
            "@@PLATFORM_BLOCK@@"
          ]
          [
            optionAsAltLine
            navigationMode
            colorAutomationBlock
            platformBlock
          ]
          rioConfigTemplate
      );
    in
    {
      xdg.configFile = {
        "rio/config.toml" = {
          force = true;
          source = rioConfig;
        };
      };
    };
}

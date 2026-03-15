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

  myconfig = {
    always = dotlib.mkEnableDefault "tools.terminal.rio.enable";
    ifEnabled = { myconfig, ... }:
      dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);
  };

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
      rioConfig = pkgs.writeText "rio-config.toml" ''
        # Root keys must stay above any [section] tables.
        line-height = 1.08
        padding-x = 10
        padding-y = [8, 8]
        hide-mouse-cursor-when-typing = true
        confirm-before-quit = true
        ${optionAsAltLine}
        [fonts]
        family = "0xProto Nerd Font"
        size = 15
        hinting = true

        [cursor]
        shape = "beam"
        blinking = false

        [bell]
        audio = false
        visual = false

        [keyboard]
        ime-cursor-positioning = true

        [navigation]
        mode = "${navigationMode}"
        use-split = true
        hide-if-single = true
        unfocused-split-opacity = 0.92
        ${colorAutomationBlock}
        [renderer]
        backend = "Automatic"
        disable-occluded-render = true
        strategy = "events"

        ${platformBlock}
        [title]
        content = "{{program}} - {{title || absolute_path}}"
      '';
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

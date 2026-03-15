{ delib, lib, dotlib, pkgs, repoPaths, ... }:

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

  myconfig = {
    always = dotlib.mkEnableDefault "tools.terminal.wezterm.enable";
    ifEnabled = { myconfig, ... }:
      dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);
  };

  home.ifEnabled = { ... }:
    let
      weztermConfig = pkgs.writeText "wezterm.lua" ''
        local wezterm = require 'wezterm'
        local act = wezterm.action

        local config = {}
        if wezterm.config_builder then
          config = wezterm.config_builder()
        end

        config.color_scheme = 'Tokyo Night'

        config.font = wezterm.font_with_fallback {
          'JetBrains Mono',
          -- Add a preferred Japanese monospace font here if needed.
        }
        config.font_size = 13.5

        config.use_ime = true

        config.window_padding = {
          left = 8,
          right = 8,
          top = 6,
          bottom = 4,
        }

        config.use_fancy_tab_bar = false
        config.hide_tab_bar_if_only_one_tab = true
        config.tab_max_width = 28

        config.inactive_pane_hsb = {
          saturation = 0.9,
          brightness = 0.8,
        }

        config.scrollback_lines = 10000

        -- Uncomment if you want a touch of transparency.
        -- config.window_background_opacity = 0.96

        -- Safe macOS title bar integration.
        -- config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'

        -- Disable ligatures if you prefer literal operator rendering.
        -- config.harfbuzz_features = { 'calt=0', 'clig=0', 'liga=0' }

        -- Tmux-like multiplexer bindings.
        -- config.leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 }
        -- config.keys = {
        --   { key = 'a', mods = 'LEADER|CTRL', action = act.SendKey { key = 'a', mods = 'CTRL' } },
        --   { key = 's', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },
        --   { key = 'v', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
        --   { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
        --   { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },
        --   { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
        --   { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
        --   { key = 'H', mods = 'LEADER', action = act.AdjustPaneSize { 'Left', 5 } },
        --   { key = 'J', mods = 'LEADER', action = act.AdjustPaneSize { 'Down', 5 } },
        --   { key = 'K', mods = 'LEADER', action = act.AdjustPaneSize { 'Up', 5 } },
        --   { key = 'L', mods = 'LEADER', action = act.AdjustPaneSize { 'Right', 5 } },
        --   { key = 'c', mods = 'LEADER', action = act.SpawnCommandInNewTab {} },
        --   { key = 'n', mods = 'LEADER', action = act.ActivateTabRelative(1) },
        --   { key = 'p', mods = 'LEADER', action = act.ActivateTabRelative(-1) },
        --   { key = 'o', mods = 'LEADER', action = act.PaneSelect },
        --   { key = 'x', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },
        --   { key = 'P', mods = 'LEADER|SHIFT', action = act.ActivateCommandPalette },
        -- }

        return config
      '';
    in
    {
      xdg.configFile."wezterm/wezterm.lua" = {
        force = true;
        source = weztermConfig;
      };
    };
}

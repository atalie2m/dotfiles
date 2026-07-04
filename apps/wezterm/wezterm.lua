local wezterm = require 'wezterm'

local config = {}
if wezterm.config_builder then
  config = wezterm.config_builder()
end

config.color_scheme = 'Catppuccin Mocha'
config.check_for_updates = false

config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'JetBrains Mono',
}
config.font_size = 14.0

config.use_ime = true
config.window_background_opacity = 0.92
config.macos_window_background_blur = 20
config.native_macos_fullscreen_mode = true
config.adjust_window_size_when_changing_font_size = false

config.window_padding = {
  left = 8,
  right = 8,
  top = 8,
  bottom = 8,
}

config.use_fancy_tab_bar = false
config.hide_tab_bar_if_only_one_tab = true
config.tab_max_width = 28
config.enable_scroll_bar = true

config.default_cursor_style = 'SteadyBar'
config.cursor_blink_rate = 0
config.audible_bell = 'Disabled'

config.inactive_pane_hsb = {
  saturation = 0.9,
  brightness = 0.8,
}

config.scrollback_lines = 30000

-- Safe macOS title bar integration.
-- config.window_decorations = 'INTEGRATED_BUTTONS|RESIZE'

return config

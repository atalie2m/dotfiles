_: {
  # Terminal configurations - import all terminal-related modules
  imports = [
    ./terminals/rio.nix
    ./terminals/terminal-app.nix
    # ./terminals/iterm2.nix     # Uncomment to enable iTerm2 config
    # ./terminals/alacritty.nix  # Uncomment to enable Alacritty config
    # ./terminals/kitty.nix      # Uncomment to enable Kitty config
  ];
}

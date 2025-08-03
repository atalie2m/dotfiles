_: {
  # iTerm2 terminal configuration (disabled by default)
  # Uncomment and configure as needed

  # Note: iTerm2 configuration through Nix/Home Manager is limited
  # Most configurations need to be done manually through iTerm2 preferences

  # programs.iterm2 = {
  #   enable = false;
  # };

  # Alternative approach: Use activation script for iTerm2 configuration
  # home.activation.configureiTerm2 = lib.hm.dag.entryAfter ["writeBoundary"] ''
  #   # iTerm2 configuration commands here
  # '';
}

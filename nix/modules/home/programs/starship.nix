_: {
  # Starship prompt configuration
  programs.starship = {
    enable = true;
    enableZshIntegration = true;  # Ensure zsh integration is enabled
    # Use external TOML file for exact preset compatibility
    settings = builtins.fromTOML (builtins.readFile ../../../../apps/starship.toml);
  };
}
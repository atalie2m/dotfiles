_: {
  # Rio terminal configuration
  programs.rio = {
    enable = true;
    settings = {
      fonts = {
        family = "0xProto Nerd Font";
        size = 11;
      };

      window = {
        opacity = 0.8;
      };

      # Additional Rio-specific configurations can be added here
      # For example:
      # theme = "dracula";
      # cursor = {
      #   shape = "block";
      #   blinking = false;
      # };
    };
  };
}

{ self, username, ... }:

{
  imports = [
    ../../../modules/homebrew
  ];

  # Enable Home Manager integration
  users.users.${username} = {
    name = username;
    home = "/Users/${username}";
  };

  # Nix configuration
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Mac-specific system configuration
  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    stateVersion = 6;
    primaryUser = username;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
      };

      finder = {
        AppleShowAllFiles = true;
        AppleShowAllExtensions = true;
      };

      dock = {
        autohide = true;
      };
    };
  };
}

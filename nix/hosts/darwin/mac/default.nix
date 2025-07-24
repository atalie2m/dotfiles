{ self, ... }:

{
  imports = [
    ../../../modules/homebrew
  ];

  # Nix configuration
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Mac-specific system configuration
  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    stateVersion = 6;
    primaryUser = "{{USER_NAME}}";
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

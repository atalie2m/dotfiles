{ self, username, ... }:

let
  env = import ../../../env.nix;
in
{
  # Enable Home Manager integration
  users.users.${username} = {
    name = username;
    home = env.defaults.homeDirectory username;
  };

  # Nix configuration
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Mac-specific system configuration
  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    stateVersion = env.defaults.stateVersion.darwin;
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

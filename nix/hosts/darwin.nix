{ self, username, ... }:

let
  env = import ../env.nix;
in
{
  # Essential user configuration
  users.users.${username} = {
    name = username;
    home = env.defaults.homeDirectory username;
  };

  # Essential Nix configuration
  nix.settings.experimental-features = "nix-command flakes";
  nixpkgs.hostPlatform = "aarch64-darwin";

  # Essential system configuration
  system = {
    configurationRevision = self.rev or self.dirtyRev or null;
    stateVersion = env.defaults.stateVersion.darwin;
    primaryUser = username;
  };
}
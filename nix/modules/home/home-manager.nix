{ config, pkgs, ... }:

let
  env = import ../../env.nix;
in
{
  imports = [
    ./packages.nix
    ./shells/bash.nix
    ./programs/git.nix
    ./programs/gpg.nix
    ./shells/zsh.nix
    ./programs/starship.nix
    ./programs/terminals.nix
    ./fonts.nix
    ./services/smart-backup.nix
    ./karabiner.nix
  ];

  home = {
    stateVersion = env.defaults.stateVersion.home;
  };

  # Smart backup service configuration
  services.smartBackup = {
    enable = true;
    files = [
      "$HOME/Library/Preferences/com.apple.Terminal.plist"
      "$HOME/.config/rio/config.toml"
      # Add more files here as needed
    ];
    backupSuffix = "backup";
    timestampFormat = "%Y%m%d-%H%M%S";
  };

  programs.home-manager.enable = true;
}

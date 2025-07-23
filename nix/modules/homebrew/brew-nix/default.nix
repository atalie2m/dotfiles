{ config, pkgs, lib, ... }:

with lib;

{
  options.homebrew.brew-nix = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable brew-nix package manager";
    };

    packages = mkOption {
      type = types.listOf types.package;
      default = [ pkgs.brewCasks.latest pkgs.brewCasks.rio ];
      description = "List of packages to install via brew-nix";
    };

    disableTraditionalHomebrew = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to disable traditional homebrew when using brew-nix";
    };
  };  config = mkIf config.homebrew.brew-nix.enable {
    # Enable brew-nix
    brew-nix.enable = true;

    # Install packages using brew-nix
    environment.systemPackages = config.homebrew.brew-nix.packages;

    # Optionally disable traditional homebrew
    homebrew.enable = mkIf config.homebrew.brew-nix.disableTraditionalHomebrew false;
  };
}

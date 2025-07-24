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
      default = [ ];
      description = "List of packages to install via brew-nix";
    };

    disableTraditionalHomebrew = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to disable traditional homebrew when using brew-nix";
    };
  };

  config = mkIf config.homebrew.brew-nix.enable {
    brew-nix.enable = true;

    environment.systemPackages = config.homebrew.brew-nix.packages;
  };
}

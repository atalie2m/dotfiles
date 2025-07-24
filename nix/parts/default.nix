{ inputs, config, ... }:

{
  flake = {
    # System configurations
    darwinConfigurations."{{LOCAL_HOSTNAME}}" =
      inputs.nix-darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        modules = [
          inputs.brew-nix.darwinModules.default
          ../modules/darwin
          ../hosts/darwin/mac
        ];
        specialArgs = { inherit (inputs) self brew-nix; };
      };

    # Home Manager configurations
    homeConfigurations."{{LOCAL_HOSTNAME}}" =
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages.aarch64-darwin;
        modules = [
          ../modules/home/home-manager.nix
        ];
      };

    # Module exports for reusability
    nixosModules = {
      darwin = ../modules/darwin;
      home = ../modules/home;
    };

    darwinModules = {
      default = ../modules/darwin;
      homebrew = ../modules/homebrew;
      mac-host = ../hosts/darwin/mac;
    };

    homeManagerModules = {
      default = ../modules/home;
      programs = ../modules/home/programs;
    };
  };

  # Development environment
  perSystem = { pkgs, ... }: {
    # Build packages and convenience scripts
    packages = {
      default = inputs.self.darwinConfigurations."{{LOCAL_HOSTNAME}}".system;

      build-darwin = pkgs.writeShellScriptBin "build-darwin" ''
        darwin-rebuild switch --flake ${inputs.self}#u1s-MacBook-Air
      '';

      build-home = pkgs.writeShellScriptBin "build-home" ''
        home-manager switch --flake ${inputs.self}#u1s-MacBook-Air
      '';
    };
  };
}

{ nix-darwin, self, brew-nix }:

nix-darwin.lib.darwinSystem {
  modules = [
    # Import brew-nix module
    brew-nix.darwinModules.default

    # Nix configuration
    ({ pkgs, lib, ... }: {
      nix.settings.experimental-features = "nix-command flakes";

      system.configurationRevision = self.rev or self.dirtyRev or null;
      system.stateVersion = 6;

      nixpkgs.hostPlatform = "aarch64-darwin";
    })

    # System configuration
    ({ pkgs, ... }: {
      system = {
        primaryUser = "{{USER_NAME}}";
        defaults = {
          NSGlobalDomain.AppleShowAllExtensions = true;
          finder = {
            AppleShowAllFiles = true;
            AppleShowAllExtensions = true;
          };
          dock = {
            autohide = true;
          };
        };
      };
    })

    # Brew configuration using brew-nix
    ({ pkgs, ... }: {
      # Enable brew-nix
      brew-nix.enable = true;

      # Install packages using brew-nix
      environment.systemPackages = [
        pkgs.brewCasks.latest
      ];

      # Keep traditional homebrew disabled since we're using brew-nix
      homebrew.enable = false;
    })
  ];

  specialArgs = { inherit self brew-nix; };
}

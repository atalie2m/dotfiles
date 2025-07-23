{ nix-darwin, self, brew-nix, brewNixModule }:

nix-darwin.lib.darwinSystem {
  modules = [
    # Import brew-nix module
    brew-nix.darwinModules.default

    # Import my custom brew-nix configuration module
    brewNixModule

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
  ];

  specialArgs = { inherit self brew-nix; };
}

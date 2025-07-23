{ nix-darwin, self }:

nix-darwin.lib.darwinSystem {
  modules = [
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

  specialArgs = { inherit self; };
}

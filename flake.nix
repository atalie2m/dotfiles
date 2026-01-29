{
  description = "Atalie's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    denix = {
      url = "github:yunfachi/denix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-darwin.follows = "nix-darwin";
        home-manager.follows = "home-manager";
      };
    };

    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nix-darwin.follows = "nix-darwin";
        brew-api.follows = "brew-api";
      };
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Local facts (non-flake)
    local = {
      url = "path:./nix/local";
      flake = false;
    };

    # Local secrets (non-flake)
    secrets = {
      url = "path:./nix/secrets";
      flake = false;
    };
  };

  # Ensure experimental features are available when operating on this flake
  nixConfig = {
    extra-experimental-features = [ "nix-command" "flakes" ];
  };

  outputs = { denix, ... } @ inputs: let
    localStub = builtins.pathExists (inputs.local + "/STUB");
    mkConfigurations = moduleSystem:
      let
        facts = import (inputs.local + "/facts.nix");
        user = facts.user or {};
        username = user.username or "";
        _ = if username == "" then
          throw "facts.user.username is required (set in ~/.config/dotfiles-local/facts.nix or override inputs.local)"
        else
          null;
      in
      builtins.seq _ (denix.lib.configurations {
        inherit moduleSystem;
        homeManagerUser = username;
        # Point Denix to the base directory; it discovers hosts/modules/rices
        # under this root. Passing subdirectories can cause path resolution
        # issues in umport.
        paths = [ ./nix/denix ];
        extensions = with denix.lib.extensions; [
          args
          (base.withConfig { args.enable = true; })
        ];
        specialArgs = { inherit inputs; };
        # Import external modules
        extraModules =
          (if moduleSystem == "darwin" then [
            inputs.brew-nix.darwinModules.default
          ] else []);
      });
  in {
    # Public flake templates for easy reuse
    templates = {
      web-dev = {
        path = ./templates/web-dev;
        description = "Web development template: devShell with Node 22, pnpm, bun, wrangler, awscli2, jq/yq, mkcert, just; Prettier formatting via treefmt-nix; apps.dev/apps.format and checks";
      };
    };
  } // (if localStub then {} else {
    homeConfigurations = mkConfigurations "home";
    darwinConfigurations = mkConfigurations "darwin";
  });
}

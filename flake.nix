{
  description = "Atalie's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.11";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
    };

    homebrew-emacs-plus = {
      url = "github:d12frosted/homebrew-emacs-plus";
      flake = false;
    };

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

    mac-app-util = {
      url = "github:hraban/mac-app-util";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secrets management
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Local facts (non-flake). Do not lock these path inputs with narHash in
    # flake.lock: Nix then fetches path:./…?narHash=… and errors on “relative path”
    # once the flake source is realised in the store (common in CI).
    local = {
      url = "path:./nix/local";
      flake = false;
    };

    # Default secrets input is intentionally inert: the repo ships no
    # `secrets.nix`, and machines override this input to a local path when
    # secrets are actually needed.
    secrets = {
      url = "path:./nix/local";
      flake = false;
    };
  };

  # Ensure experimental features are available when operating on this flake
  nixConfig = {
    extra-experimental-features = [ "nix-command" "flakes" ];
  };

  outputs = inputs @ { denix, flake-parts, ... }:
    let
      nixLib = inputs.nixpkgs.lib;
      dotlib = import ./nix/lib { lib = nixLib; };

      repoPaths = rec {
        root = ./.;
        apps = root + "/apps";
        catalog = root + "/nix/catalog";
        keyboards = root + "/keyboards";
        nixScripts = root + "/nix/scripts";
        scripts = root + "/scripts";
        surfaces = root + "/surfaces";
      };

      nixCatalog = import ./nix/catalog/tools/nixpkgs.nix;
      homebrewOwnership = import ./nix/catalog/tools/homebrew-ownership.nix;

      toolOwnershipLib = import ./nix/lib/tool-ownership.nix {
        lib = nixLib;
        inherit nixCatalog homebrewOwnership;
      };

      portable = import ./nix/flake/portable.nix {
        inherit inputs nixLib repoPaths;
      };

      configurations = import ./nix/flake/configurations.nix {
        inherit inputs denix dotlib repoPaths;
      };

      darwinConfigurations = configurations.darwinConfigurations;

      perSystemModule = import ./nix/flake/per-system.nix {
        inherit inputs repoPaths dotlib toolOwnershipLib darwinConfigurations;
        inherit (portable)
          mkDotfilesCliPackage
          mkDotfilesPackage
          mkSyncVscodeRustPackage
          mkPortableChecks
          mkPortableDevShell
          treefmtConfigFor
          ;
      };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];
      systems = [ "aarch64-darwin" "x86_64-darwin" ];

      perSystem = perSystemModule;

      flake = {
        # Public flake templates for easy reuse
        templates = {
          web-dev = {
            path = ./templates/web-dev;
            description = "Web development template: devShell with Node 22, pnpm, bun, optional wrangler, awscli2, jq/yq, mkcert, just; Prettier formatting via treefmt-nix; apps.dev/apps.format and checks";
          };
          rust-dev = {
            path = ./templates/rust-dev;
            description = "Rust development template: stable toolchain (rust-overlay, rust-src), rust-analyzer, libclang/pkg-config, cargo-nextest/bacon/deny/llvm-cov/expand/sccache, cmake/ninja/protobuf/sqlite";
          };
        };
        inherit darwinConfigurations;
      };
    };
}

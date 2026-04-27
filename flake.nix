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

    doom-meow = {
      url = "github:meow-edit/doom-meow";
      flake = false;
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

  outputs = inputs @ { flake-parts, ... }:
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
        inherit inputs dotlib repoPaths;
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
            description = "Web development template: Node 22/corepack, pnpm, bun, deno, TypeScript tooling, Workers/Netlify/Supabase helpers, treefmt-nix, git-hooks.nix, security checks";
          };
          rust-dev = {
            path = ./templates/rust-dev;
            description = "Rust development template: rust-overlay stable toolchain, rust-analyzer, cargo QA/release tools, treefmt-nix, git-hooks.nix, security checks";
          };
          go-dev = {
            path = ./templates/go-dev;
            description = "Go service/CLI template with gopls, golangci-lint, gofumpt, govulncheck, gotestsum, goreleaser, ko, and common checks";
          };
          python-research = {
            path = ./templates/python-research;
            description = "Python, notebook, ML, and research template with uv, pixi, ruff, pyright, pytest, Jupyter, DVC/data tooling, and common checks";
          };
          data-pipeline = {
            path = ./templates/data-pipeline;
            description = "CSV/JSON/Parquet/SQL data pipeline template with duckdb, qsv, xan, miller, jq/yq, visidata, and common checks";
          };
          native-dev = {
            path = ./templates/native-dev;
            description = "C/C++/Zig native template with cmake, ninja, meson, clang/LLVM, sanitizing/debugging tools, and common checks";
          };
          embedded-dev = {
            path = ./templates/embedded-dev;
            description = "Embedded/MCU/FPGA template with ARM, flashing, serial, QEMU/Renode, Verilator/Yosys, and common checks";
          };
          apple-dev = {
            path = ./templates/apple-dev;
            description = "iOS/macOS/Swift template with tuist, xcodegen, swiftlint, swiftformat, fastlane, CocoaPods, and common checks";
          };
          infra-nixos = {
            path = ./templates/infra-nixos;
            description = "NixOS/Home infra template with colmena, deploy-rs, disko, nixos-anywhere, sops/age, cache tooling, and common checks";
          };
          infra-iac = {
            path = ./templates/infra-iac;
            description = "Terraform/OpenTofu/cloud IaC template with project-local Terraform unfree allow-list, terragrunt, tflint, checkov, infracost, and common checks";
          };
          kubernetes-dev = {
            path = ./templates/kubernetes-dev;
            description = "Kubernetes/Helm/cluster app template with kubectl, kustomize, helm, kind/k3d, tilt, skaffold, k9s, and supply-chain checks";
          };
          container-oci = {
            path = ./templates/container-oci;
            description = "Container image and OCI artifact template with docker, podman, buildah, skopeo, oras, crane, regctl, dive, and supply-chain checks";
          };
          model-hf = {
            path = ./templates/model-hf;
            description = "Hugging Face/model artifact template with git-lfs, huggingface_hub, rclone, DVC/data tooling, and secret scanning";
          };
          docs-dev = {
            path = ./templates/docs-dev;
            description = "Docs/static site/PDF template with pandoc, quarto, typst, mdbook, mermaid, graphviz, plantuml, d2, vale, and common checks";
          };
          api-db = {
            path = ./templates/api-db;
            description = "API and database template with hurl, bruno-cli, grpcurl, load tools, SQL clients, local services, migration CLIs, and common checks";
          };
          ai-coding = {
            path = ./templates/ai-coding;
            description = "Repo-pinned AI coding workflow template with aider, llm, Goose, uv, Node 22, pnpm, ripgrep, ast-grep, semgrep, and common checks";
          };
          release-dev = {
            path = ./templates/release-dev;
            description = "Release/changelog/signing template with git-cliff, goreleaser, cargo-dist/release, cosign, SLSA, OCI tools, and common checks";
          };
        };
        inherit darwinConfigurations;
      };
    };
}

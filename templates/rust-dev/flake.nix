{
  description = "Rust project template with rust-overlay, common checks, security tooling, and release helpers";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ { flake-parts, treefmt-nix, git-hooks-nix, rust-overlay, ... }:
    let
      unsafeFlakeSource =
        builtins.any
          (dir: builtins.pathExists (./. + "/${dir}"))
          [
            "target"
            "node_modules"
            ".git"
            ".direnv"
          ];
    in
    if unsafeFlakeSource then
      throw ''
        Refusing to evaluate this flake because target/, node_modules/, .git/, or .direnv/ is present in the flake source.

        Use Git flake refs such as .#..., not path:$PWD#...
      ''
    else flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      imports = [
        treefmt-nix.flakeModule
        git-hooks-nix.flakeModule
      ];

      perSystem = { system, config, lib, ... }:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfreePredicate = pkg:
              builtins.elem (lib.getName pkg) [
                "crush"
                "terraform"
              ];
          };
          rustPkgs = pkgs.extend rust-overlay.overlays.default;
          rustToolchain = rustPkgs.rust-bin.stable.latest.default.override {
            extensions = [
              "rust-src"
              "llvm-tools-preview"
            ];
          };
          enabledProfiles = [
            # "api-db"
            # "docs"
            # "release"
            # "container-oci"
            # "kubernetes"
            # "infra-iac"
            # "ai-coding"
            # "model-hf"
            # "native-debug"
          ];
          optionalProfiles = import ./optional-profiles.nix { inherit lib pkgs; };
          selectedProfilePackages = lib.concatMap
            (profile:
              optionalProfiles.${profile} or (throw "Unknown optional profile '${profile}'. Available profiles: ${lib.concatStringsSep ", " (builtins.attrNames optionalProfiles)}"))
            enabledProfiles;
          commonPackages = with pkgs; [
            zsh
            devenv
            process-compose
            direnv
            nix-direnv
            just
            pre-commit
            lefthook
            treefmt
            editorconfig-checker
            typos
            lychee
            reuse
            taplo
            yamlfmt
            yamllint
            check-jsonschema
            shellcheck
            shfmt
            statix
            deadnix
            alejandra
            nixfmt
            nixpkgs-fmt
          ];
          securityPackages = with pkgs; [
            gitleaks
            trufflehog
            noseyparker
            osv-scanner
            semgrep
            ast-grep
            pip-audit
            ssh-audit
            minisign
            actionlint
            zizmor
            trivy
            grype
            syft
            cosign
            cargo-deny
            cargo-audit
          ];
          rustPackages = with pkgs; [
            rustToolchain
            rustup
            rust-analyzer
            pkg-config
            llvmPackages.libclang
            cargo-nextest
            cargo-watch
            bacon
            cargo-machete
            cargo-udeps
            cargo-llvm-cov
            cargo-mutants
            cargo-tarpaulin
            cargo-expand
            cargo-insta
            cargo-bloat
            cargo-outdated
            cargo-semver-checks
            sccache
            mold
            lld
            cargo-zigbuild
            cargo-dist
            cargo-release
            git-cliff
            sqlx-cli
            diesel-cli
            maturin
            cmake
            ninja
            protobuf
            sqlite
          ];
        in
        {
          devShells.default = pkgs.mkShell {
            name = "rust-dev";
            packages = commonPackages ++ securityPackages ++ rustPackages ++ selectedProfilePackages;
            shellHook = ''
              ${config.pre-commit.installationScript}
              export LIBCLANG_PATH="${pkgs.llvmPackages.libclang.lib}/lib"
              echo "rust-dev: $(rustc -vV | head -n1), $(cargo -V)"
              if [[ -z "''${ZSH_VERSION:-}" && $- == *i* ]]; then
                exec ${pkgs.zsh}/bin/zsh -i
              fi
            '';

            apps = {
              format = {
                type = "app";
                program = "${config.treefmt.build.wrapper}/bin/treefmt";
              };
              test = {
                type = "app";
                program = "${pkgs.writeShellScript "rust-test" ''
                set -euo pipefail
                cargo nextest run "$@"
              ''}";
              };
            };

            formatter = config.treefmt.build.wrapper;
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixpkgs-fmt.enable = true;
              shfmt.enable = true;
              rustfmt.enable = true;
              taplo.enable = true;
            };
          };

          pre-commit.settings.hooks = {
            actionlint.enable = true;
            cargo-check.enable = true;
            clippy.enable = true;
            deadnix.enable = true;
            editorconfig-checker.enable = true;
            nixpkgs-fmt.enable = true;
            rustfmt.enable = true;
            shellcheck.enable = true;
            shfmt.enable = true;
            statix.enable = true;
            taplo.enable = true;
            typos.enable = true;
          };

          checks.flake-source-hygiene = pkgs.runCommand "flake-source-hygiene" { src = ./.; } ''
            set -euo pipefail
            for dir in target node_modules .git .direnv; do
              if [ -e "$src/$dir" ]; then
                echo "FAIL: $dir is present in the Nix flake source." >&2
                echo "Use Git flake refs such as .#..., not path:\$PWD#..., and keep large generated directories ignored." >&2
                exit 1
              fi
            done
            touch "$out"
          '';

          apps = {
            format = {
              type = "app";
              program = "${config.treefmt.build.wrapper}/bin/treefmt";
            };
            test = {
              type = "app";
              program = "${pkgs.writeShellScript "rust-test" ''
                set -euo pipefail
                cargo nextest run "$@"
              ''}";
            };
          };

          formatter = config.treefmt.build.wrapper;
        };
    };
}

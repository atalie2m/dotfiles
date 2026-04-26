{
  description = "Release / changelog / signing project template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = { url = "github:numtide/treefmt-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    git-hooks-nix = { url = "github:cachix/git-hooks.nix"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = inputs @ { flake-parts, treefmt-nix, git-hooks-nix, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      imports = [ treefmt-nix.flakeModule git-hooks-nix.flakeModule ];

      perSystem = { pkgs, config, ... }: {
        devShells.default = pkgs.mkShell {
          name = "release-dev";
          packages = with pkgs; [
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
            gitleaks
            trufflehog
            noseyparker
            osv-scanner
            semgrep
            pip-audit
            ssh-audit
            minisign
            actionlint
            zizmor
            git-cliff
            goreleaser
            cargo-dist
            cargo-release
            cosign
            slsa-verifier
            syft
            grype
            trivy
            oras
            crane
            regctl
            dive
            gh
          ];
          shellHook = ''
            ${config.pre-commit.installationScript}
            if [[ -z "''${ZSH_VERSION:-}" && $- == *i* ]]; then
              exec ${pkgs.zsh}/bin/zsh -i
            fi
          '';
        };
        treefmt = { projectRootFile = "flake.nix"; programs = { nixpkgs-fmt.enable = true; shfmt.enable = true; taplo.enable = true; }; };
        pre-commit.settings.hooks = {
          actionlint.enable = true;
          deadnix.enable = true;
          editorconfig-checker.enable = true;
          nixpkgs-fmt.enable = true;
          shellcheck.enable = true;
          shfmt.enable = true;
          statix.enable = true;
          taplo.enable = true;
          typos.enable = true;
        };
        apps.format = { type = "app"; program = "${config.treefmt.build.wrapper}/bin/treefmt"; };
        formatter = config.treefmt.build.wrapper;
      };
    };
}

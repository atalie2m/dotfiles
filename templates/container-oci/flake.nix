{
  description = "Container image / OCI artifact / registry workflow template";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix = { url = "github:numtide/treefmt-nix"; inputs.nixpkgs.follows = "nixpkgs"; };
    git-hooks-nix = { url = "github:cachix/git-hooks.nix"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = inputs @ { flake-parts, treefmt-nix, git-hooks-nix, ... }:
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
      imports = [ treefmt-nix.flakeModule git-hooks-nix.flakeModule ];
      perSystem = { pkgs, config, ... }: {
        devShells.default = pkgs.mkShell {
          name = "container-oci";
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
            docker
            podman
            buildah
            skopeo
            oras
            crane
            regctl
            dive
            trivy
            syft
            grype
            cosign
            slsa-verifier
            ko
            goreleaser
            gitleaks
            trufflehog
            noseyparker
            actionlint
            zizmor
          ];
          shellHook = ''
            ${config.pre-commit.installationScript}
            if [[ -z "''${ZSH_VERSION:-}" && $- == *i* ]]; then exec ${pkgs.zsh}/bin/zsh -i; fi
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
        apps.format = { type = "app"; program = "${config.treefmt.build.wrapper}/bin/treefmt"; };
        formatter = config.treefmt.build.wrapper;
      };
    };
}

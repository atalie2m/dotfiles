{
  description = "Web / TypeScript project template with pinned Node 22, common checks, and security tooling";

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
          node = pkgs.nodejs_22;
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
            dotenv-linter
            shellcheck
            shfmt
            bashate
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
            ghalint
            pinact
            poutine
            trivy
            grype
            syft
            cosign
            slsa-verifier
          ];
          webPackages = with pkgs; [
            node
            pnpm
            bun
            deno
            yarn
            typescript
            tsx
            playwright
            biome
            oxlint
            eslint
            prettier
            stylelint
            turbo

            netlify-cli
            supabase-cli
            turso-cli
            wrangler
            prisma
            redocly
            mkcert
            awscli2
            jq
            yq
            redis
            postgresql
            mailpit
            minio
          ];
        in
        {
          devShells.default = pkgs.mkShell {
            name = "web-dev";
            packages = commonPackages ++ securityPackages ++ webPackages ++ selectedProfilePackages;
            shellHook = ''
              ${config.pre-commit.installationScript}
              corepack enable --install-directory "$PWD/.direnv/bin" 2>/dev/null || true
              echo "web-dev: Node $(node -v), pnpm $(pnpm -v), bun $(bun --version)"
              if [[ -z "''${ZSH_VERSION:-}" && $- == *i* ]]; then
                exec ${pkgs.zsh}/bin/zsh -i
              fi
            '';
          };

          treefmt = {
            projectRootFile = "flake.nix";
            programs = {
              nixpkgs-fmt.enable = true;
              shfmt.enable = true;
              prettier.enable = true;
              taplo.enable = true;
            };
            settings.formatter.prettier.includes = [
              "**/*.{js,jsx,ts,tsx,mjs,cjs,css,scss,html,md,json,yml,yaml}"
            ];
          };

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

          apps = {
            dev = {
              type = "app";
              program = "${pkgs.writeShellScript "web-dev" ''
                set -euo pipefail
                if [ -f package.json ]; then
                  if [ -f pnpm-lock.yaml ]; then
                    pnpm install
                  elif [ -f bun.lockb ]; then
                    bun install
                  else
                    npm install
                  fi
                fi
                exec just dev "$@"
              ''}";
            };
            format = {
              type = "app";
              program = "${config.treefmt.build.wrapper}/bin/treefmt";
            };
            check = {
              type = "app";
              program = "${pkgs.writeShellScript "web-check" ''
                set -euo pipefail
                ${config.treefmt.build.wrapper}/bin/treefmt --fail-on-change
                nix flake check
              ''}";
            };
          };

          formatter = config.treefmt.build.wrapper;
        };
    };
}

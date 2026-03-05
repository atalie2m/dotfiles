{
  description = "Atalie's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.05-darwin";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-25.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew = {
      url = "github:zhaofengli/nix-homebrew";
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

  outputs = inputs @ { denix, flake-parts, ... }:
    let
      localStub = builtins.pathExists (inputs.local + "/STUB");
      dotlib = import ./nix/lib { lib = inputs.nixpkgs.lib; };
      mkConfigurations = { moduleSystem, paths }:
        let
          facts = import (inputs.local + "/facts.nix");
          user = facts.user or { };
          username = user.username or "";
          _ =
            if username == "" then
              throw "facts.user.username is required (set in ~/.config/dotfiles/facts.nix or override inputs.local)"
            else
              null;
        in
        builtins.seq _ (denix.lib.configurations {
          inherit moduleSystem;
          homeManagerUser = username;
          inherit paths;
          extensions = with denix.lib.extensions; [
            args
            (base.withConfig { args.enable = true; })
          ];
          specialArgs = { inherit inputs dotlib; };
        });

      configurationPaths = {
        darwin = [
          ./nix/denix/modules
          ./nix/denix/darwin/hosts
          ./nix/denix/darwin/rices
        ];
        nixos = [
          ./nix/denix/modules
          ./nix/denix/nixos/hosts
          ./nix/denix/nixos/rices
        ];
        home = [
          ./nix/denix/modules
          ./nix/denix/home/hosts
          ./nix/denix/home/rices
        ];
      };

      mkLatestConfigurations = moduleSystem:
        mkConfigurations {
          inherit moduleSystem;
          paths = configurationPaths.${moduleSystem}
            or (throw "unsupported moduleSystem '${moduleSystem}'");
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

      perSystem = { pkgs, config, lib, ... }:
        let
          scripts = ./nix/scripts;
          dotfilesRoot = ./.;
          nixCatalog = import ./nix/data/tools/catalog-data.nix;
          brewCatalog = import ./nix/data/tools/brew-catalog-data.nix;
          catalogIds = catalog:
            builtins.map (name: "${catalog.${name}.group}.${name}") (builtins.attrNames catalog);
          catalogOverlap = lib.intersectLists (catalogIds nixCatalog) (catalogIds brewCatalog);
          catalogOverlapText =
            if catalogOverlap == [ ] then "(none)"
            else lib.concatStringsSep ", " catalogOverlap;

          mkDotfilesApp = { name, subcommand ? null, description }:
            let
              execLine =
                if subcommand == null
                then "exec ${scripts}/dotfiles.sh \"$@\""
                else "exec ${scripts}/dotfiles.sh ${subcommand} \"$@\"";
            in
            {
              type = "app";
              program = "${pkgs.writeShellScript "dotfiles-${name}" ''
                if [[ -z "''${DOTFILES_ROOT:-}" ]]; then
                  pwd_root="$(pwd)"
                  if [[ -f "$pwd_root/flake.nix" && -d "$pwd_root/nix/scripts" ]]; then
                    export DOTFILES_ROOT="$pwd_root"
                  fi
                fi
                if [[ -z "''${DOTFILES_ROOT:-}" ]] && command -v git >/dev/null 2>&1; then
                  candidate_root="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
                  if [[ -n "$candidate_root" && -f "$candidate_root/flake.nix" && -d "$candidate_root/nix/scripts" ]]; then
                    export DOTFILES_ROOT="$candidate_root"
                  fi
                fi
                export DOTFILES_ROOT="''${DOTFILES_ROOT:-${dotfilesRoot}}"
                ${execLine}
              ''}";
              meta.description = description;
            };
        in
        {
          treefmt = {
            projectRootFile = "flake.nix";
            settings.global.excludes = [ ".direnv/**" "result/**" ];
            programs.nixpkgs-fmt.enable = true;
            programs.shfmt = {
              enable = true;
              indent_size = 2;
            };
          };

          formatter = config.treefmt.build.wrapper;

          checks = {
            treefmt = lib.mkForce (pkgs.runCommand "treefmt-check"
              {
                nativeBuildInputs = [ pkgs.git config.treefmt.build.wrapper ];
                src = inputs.self;
              } ''
                            set -euo pipefail
                            project_dir="$TMPDIR/project"
                            cp -r "$src" "$project_dir"
                            chmod -R u+w "$project_dir"
                            cd "$project_dir"

                            export HOME="$TMPDIR/home"
                            mkdir -p "$HOME"
                            cat >"$HOME/.gitconfig" <<'EOF'
              [user]
                name = Nix
                email = nix@localhost
              [init]
                defaultBranch = main
              EOF
                            export GIT_CONFIG_NOSYSTEM=1
                            export LANG=en_US.UTF-8
                            export LC_ALL=en_US.UTF-8

              git init --quiet
              git add .
              git -c commit.gpgSign=false commit -m init --quiet

                            treefmt --version
                            treefmt --no-cache
                            git --no-pager diff --exit-code
                            touch "$out"
            '');

            statix = pkgs.runCommand "statix-check"
              {
                nativeBuildInputs = [ pkgs.statix ];
                src = inputs.self;
              } ''
                          cd "$src"
                          config_file=$(mktemp)
                          cat >"$config_file" <<'EOF'
              disabled = [
                "manual_inherit"
                "manual_inherit_from"
                "useless_parens"
                "empty_pattern"
                "useless_has_attr"
                "repeated_keys"
              ]
              ignore = [ ".direnv", "result" ]
              nix_version = "2.4"
              EOF
                          statix check --config "$config_file" .
                          touch "$out"
            '';

            deadnix = pkgs.runCommand "deadnix-check"
              {
                nativeBuildInputs = [ pkgs.deadnix ];
                src = inputs.self;
              } ''
              cd "$src"
              deadnix --fail -l -L .
              touch "$out"
            '';

            shellcheck = pkgs.runCommand "shellcheck-check"
              {
                nativeBuildInputs = [ pkgs.findutils pkgs.shellcheck ];
                src = inputs.self;
              } ''
              cd "$src"
              mapfile -t files < <(find nix/scripts -type f -name '*.sh' | sort)
              if [[ "''${#files[@]}" -eq 0 ]]; then
                touch "$out"
                exit 0
              fi
              shellcheck \
                -e SC1091 \
                -e SC2016 \
                -e SC2034 \
                -e SC2129 \
                -e SC2154 \
                -e SC2317 \
                "''${files[@]}"
              touch "$out"
            '';

            toolOwnership = pkgs.runCommand "tool-ownership-check" { } ''
              if [ ${toString (builtins.length catalogOverlap)} -ne 0 ]; then
                echo "Duplicate tool ownership detected between Nix and Homebrew catalogs." >&2
                echo "Overlaps: ${catalogOverlapText}" >&2
                exit 1
              fi
              touch "$out"
            '';

            syncCoreFakeAdapter = pkgs.runCommand "sync-core-fake-adapter-test"
              {
                nativeBuildInputs = [ pkgs.bash ];
                src = inputs.self;
              } ''
              cd "$src"
              bash nix/scripts/sync-core-fake-adapter-test.sh
              touch "$out"
            '';

            syncShellSmoke = pkgs.runCommand "sync-shell-smoke-test"
              {
                nativeBuildInputs = [ pkgs.bash ];
                src = inputs.self;
              } ''
              cd "$src"
              bash nix/scripts/sync-shell-smoke-test.sh
              touch "$out"
            '';

            syncCliMigration = pkgs.runCommand "sync-cli-migration-test"
              {
                nativeBuildInputs = [ pkgs.bash ];
                src = inputs.self;
              } ''
              cd "$src"
              bash nix/scripts/sync-cli-migration-test.sh
              touch "$out"
            '';

            syncCliCommonParse = pkgs.runCommand "sync-cli-common-parse-test"
              {
                nativeBuildInputs = [ pkgs.bash ];
                src = inputs.self;
              } ''
              cd "$src"
              bash nix/scripts/sync-cli-common-parse-test.sh
              touch "$out"
            '';

            shellEntrypointWriteability = pkgs.runCommand "shell-zsh-writeability-test"
              {
                nativeBuildInputs = [ pkgs.bash ];
                src = inputs.self;
              } ''
              cd "$src"
              bash nix/scripts/shell-zsh-writeability-test.sh
              touch "$out"
            '';

            vscodeInstancesSmoke = pkgs.runCommand "vscode-instances-smoke-test"
              {
                nativeBuildInputs = [ pkgs.bash pkgs.jq ];
                src = inputs.self;
              } ''
              cd "$src"
              bash nix/scripts/vscode-instances-smoke-test.sh
              touch "$out"
            '';

            syncTerminalSmoke =
              if pkgs.stdenv.isDarwin then
                pkgs.runCommand "sync-terminal-smoke-test"
                  {
                    nativeBuildInputs = [ pkgs.bash ];
                    src = inputs.self;
                  } ''
                  cd "$src"
                  bash nix/scripts/sync-terminal-smoke-test.sh
                  touch "$out"
                ''
              else
                pkgs.runCommand "sync-terminal-smoke-test-skipped" { } ''
                  touch "$out"
                '';
          };

          devShells.default = pkgs.mkShell {
            name = "dotfiles-dev";
            packages = [
              pkgs.age
              pkgs.deadnix
              pkgs.nvfetcher
              pkgs.shellcheck
              pkgs.sops
              pkgs.statix
              config.treefmt.build.wrapper
            ];
          };

          apps = {
            dotfiles = mkDotfilesApp {
              name = "cli";
              description = "Unified dotfiles CLI (apply/update/doctor/bootstrap/list-tools).";
            };
            update = mkDotfilesApp {
              name = "update";
              subcommand = "update";
              description = "Update flake inputs, run checks, and build host targets.";
            };
            list-tools = mkDotfilesApp {
              name = "list-tools";
              subcommand = "list-tools";
              description = "List effective myconfig.tools values for a host/rice.";
            };
            apply = mkDotfilesApp {
              name = "apply";
              subcommand = "apply";
              description = "Build or switch nix-darwin configurations.";
            };
            doctor = mkDotfilesApp {
              name = "doctor";
              subcommand = "doctor";
              description = "Run dotfiles health checks.";
            };
            bootstrap = mkDotfilesApp {
              name = "bootstrap";
              subcommand = "bootstrap";
              description = "Initialize local facts/secrets and optionally apply.";
            };
            format = {
              type = "app";
              program = "${config.treefmt.build.wrapper}/bin/treefmt";
              meta.description = "Format Nix and shell files with treefmt.";
            };
          };
        };

      flake = {
        # Public flake templates for easy reuse
        templates = {
          web-dev = {
            path = ./templates/web-dev;
            description = "Web development template: devShell with Node 22, pnpm, bun, optional wrangler, awscli2, jq/yq, mkcert, just; Prettier formatting via treefmt-nix; apps.dev/apps.format and checks";
          };
        };
      } // (if localStub then { } else {
        nixosConfigurations = mkLatestConfigurations "nixos";
        homeConfigurations = mkLatestConfigurations "home";
        darwinConfigurations = mkLatestConfigurations "darwin";
      });
    };
}

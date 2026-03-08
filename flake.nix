{
  description = "Atalie's nix-darwin system flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-25.11-darwin";
    nixpkgs-linux.url = "github:NixOS/nixpkgs/nixos-25.11";

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
      nixLib = inputs.nixpkgs.lib;
      localStub = builtins.pathExists (inputs.local + "/STUB");
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
      brewCatalog = import ./nix/catalog/tools/homebrew.nix;
      dedicatedHomebrewCatalog = import ./nix/catalog/tools/homebrew-dedicated.nix;
      toolOwnershipLib = import ./nix/lib/tool-ownership.nix {
        lib = nixLib;
        inherit nixCatalog brewCatalog;
        dedicatedHomebrew = dedicatedHomebrewCatalog;
      };
      linuxSystems = [ "aarch64-linux" "x86_64-linux" ];
      treefmtConfigFor = pkgs: {
        projectRootFile = "flake.nix";
        settings = {
          global.excludes = [ ".direnv/**" "result/**" "flake.lock" ];
          formatter.prettier-json = {
            command = "${pkgs.nodePackages.prettier}/bin/prettier";
            includes = [ "*.json" "**/*.json" ];
            options = [ "--write" ];
          };
        };
        programs.nixpkgs-fmt.enable = true;
        programs.shfmt = {
          enable = true;
          indent_size = 2;
        };
      };
      mkPortableChecks = { pkgs, formatterWrapper }:
        {
          treefmt = pkgs.runCommand "treefmt-check"
            {
              nativeBuildInputs = [ pkgs.git formatterWrapper ];
              src = repoPaths.root;
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
          '';

          statix = pkgs.runCommand "statix-check"
            {
              nativeBuildInputs = [ pkgs.statix ];
              src = repoPaths.root;
            } ''
                        cd "$src"
                        config_file=$(mktemp)
                        cat >"$config_file" <<'EOF'
            disabled = [
              "manual_inherit",
              "manual_inherit_from",
              "useless_parens",
              "empty_pattern",
              "useless_has_attr",
              "repeated_keys",
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
              src = repoPaths.root;
            } ''
            cd "$src"
            deadnix --fail -l -L .
            touch "$out"
          '';

          shellcheck = pkgs.runCommand "shellcheck-check"
            {
              nativeBuildInputs = [ pkgs.findutils pkgs.shellcheck ];
              src = repoPaths.root;
            } ''
            cd "$src"
            mapfile -t script_files < <(find scripts -type f -name '*.sh' | sort)
            mapfile -t sourced_files < <(
              {
                if [[ -d surfaces/shell/desired ]]; then
                  find surfaces/shell/desired -type f -name '*.sh'
                fi
                if [[ -d apps/shell ]]; then
                  find apps/shell -type f -name '*.sh'
                fi
              } | sort
            )

            if [[ "''${#script_files[@]}" -eq 0 && "''${#sourced_files[@]}" -eq 0 ]]; then
              touch "$out"
              exit 0
            fi

            if [[ "''${#script_files[@]}" -gt 0 ]]; then
              shellcheck \
                -e SC1091 \
                -e SC2016 \
                -e SC2129 \
                "''${script_files[@]}"
            fi

            if [[ "''${#sourced_files[@]}" -gt 0 ]]; then
              shellcheck \
                --shell=bash \
                -e SC1091 \
                -e SC2016 \
                -e SC2129 \
                "''${sourced_files[@]}"
            fi
            touch "$out"
          '';

          syncShellSmoke = pkgs.runCommand "sync-shell-smoke-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/sync-shell-smoke-test.sh
            touch "$out"
          '';

          syncCliMigration = pkgs.runCommand "sync-cli-migration-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.git ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/sync-cli-migration-test.sh
            touch "$out"
          '';

          syncCliCommonParse = pkgs.runCommand "sync-cli-common-parse-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/sync-cli-common-parse-test.sh
            touch "$out"
          '';

          exportCleanSmoke = pkgs.runCommand "export-clean-smoke-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.gnused pkgs.gnutar ];
              src = repoPaths.root;
            } ''
            project_dir="$TMPDIR/project"
            cp -r "$src" "$project_dir"
            chmod -R u+w "$project_dir"
            cd "$project_dir"
            git init --quiet
            git add .
            bash scripts/tests/export-clean-smoke-test.sh
            touch "$out"
          '';

          shellEntrypointWriteability = pkgs.runCommand "shell-zsh-writeability-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/shell-zsh-writeability-test.sh
            touch "$out"
          '';

          zshrcCompat = pkgs.runCommand "zshrc-compat-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/zshrc-compat-test.sh
            touch "$out"
          '';

          vscodeInstancesSmoke = pkgs.runCommand "vscode-instances-smoke-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.jq ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/vscode-instances-smoke-test.sh
            touch "$out"
          '';

          retiredHostLiterals = pkgs.runCommand "retired-host-literals-test"
            {
              nativeBuildInputs = [ pkgs.bash pkgs.ripgrep ];
              src = repoPaths.root;
            } ''
            cd "$src"
            bash scripts/tests/retired-host-literals-test.sh
            touch "$out"
          '';
        };
      mkPortableDevShell = { pkgs, formatterWrapper }:
        pkgs.mkShell {
          name = "dotfiles-dev";
          packages = [
            pkgs.age
            pkgs.deadnix
            pkgs.nvfetcher
            pkgs.shellcheck
            pkgs.sops
            pkgs.statix
            formatterWrapper
          ];
        };
      linuxContributorOutputs =
        nixLib.foldl'
          nixLib.recursiveUpdate
          { }
          (map
            (system:
              let
                pkgs = import inputs.nixpkgs-linux { inherit system; };
                treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs (treefmtConfigFor pkgs);
                formatterWrapper = treefmtEval.config.build.wrapper;
              in
              {
                formatter.${system} = formatterWrapper;
                checks.${system} = mkPortableChecks { inherit pkgs formatterWrapper; };
                devShells.${system}.default = mkPortableDevShell { inherit pkgs formatterWrapper; };
                apps.${system}.format = {
                  type = "app";
                  program = "${pkgs.writeShellScript "dotfiles-format" ''
                    exec ${formatterWrapper}/bin/treefmt "$@"
                  ''}";
                  meta.description = "Format Nix and shell files with treefmt.";
                };
              })
            linuxSystems);
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
          specialArgs = { inherit inputs dotlib repoPaths; };
        });

      configurationPaths = {
        darwin = [
          ./nix/modules
          ./nix/denix/darwin/hosts
          ./nix/denix/darwin/rices
        ];
        nixos = [
          ./nix/modules
          ./nix/denix/nixos/hosts
          ./nix/denix/nixos/rices
        ];
        home = [
          ./nix/modules
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

      darwinConfigurations = if localStub then { } else mkLatestConfigurations "darwin";
      homeConfigurations = if localStub then { } else mkLatestConfigurations "home";
      nixosConfigurations = if localStub then { } else mkLatestConfigurations "nixos";
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];
      systems = [ "aarch64-darwin" "x86_64-darwin" ];

      perSystem = { pkgs, config, lib, ... }:
        let
          scripts = ./scripts;
          dotfilesRoot = repoPaths.root;
          darwinTargetNames = lib.sort (a: b: a < b) (builtins.attrNames darwinConfigurations);
          toolOwnershipReports =
            map
              (targetName: toolOwnershipLib.report targetName darwinConfigurations.${targetName}.config)
              darwinTargetNames;
          toolOwnershipFailures = lib.concatMap (report: report.failureMessages) toolOwnershipReports;
          toolOwnershipFailureText = lib.concatStringsSep "\n" toolOwnershipFailures;
          catalogValidationFailureText =
            dotlib.nixCatalogFailureMessage {
              toolKey = "core.fakeTool";
              systemName = "darwin";
              spec = {
                group = "core";
                pkgDarwin = [ "missing" "package" ];
              };
            };
          brewNixOverlapReport = toolOwnershipLib.report "test-target" {
            myconfig.tools.system.brewNix = {
              enable = true;
              casks = {
                keyclu = "KeyClu.app";
              };
              extraCasks = { };
            };
            homebrew.casks = [ "keyclu" ];
          };
          brewNixDuplicateClaimReport = toolOwnershipLib.report "test-target" {
            myconfig.tools.system = {
              brewNix = {
                enable = true;
                casks = {
                  keyclu = "KeyClu.app";
                };
                extraCasks = { };
              };
              keyclu.enable = true;
            };
            homebrew.casks = [ "keyclu" ];
          };

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
                  if [[ -f "$pwd_root/flake.nix" && -d "$pwd_root/scripts" ]]; then
                    export DOTFILES_ROOT="$pwd_root"
                  fi
                fi
                if [[ -z "''${DOTFILES_ROOT:-}" ]] && command -v git >/dev/null 2>&1; then
                  candidate_root="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
                  if [[ -n "$candidate_root" && -f "$candidate_root/flake.nix" && -d "$candidate_root/scripts" ]]; then
                    export DOTFILES_ROOT="$candidate_root"
                  fi
                fi
                export DOTFILES_ROOT="''${DOTFILES_ROOT:-${dotfilesRoot}}"
                ${execLine}
              ''}";
              meta.description = description;
            };
          portableChecks = mkPortableChecks {
            inherit pkgs;
            formatterWrapper = config.treefmt.build.wrapper;
          };
        in
        {
          treefmt = treefmtConfigFor pkgs;

          formatter = config.treefmt.build.wrapper;

          checks = portableChecks // {
            treefmt = lib.mkForce portableChecks.treefmt;
            toolOwnership = pkgs.runCommand "tool-ownership-check" { } ''
                            if [ ${toString (builtins.length toolOwnershipFailures)} -ne 0 ]; then
                              cat >&2 <<'EOF'
              ${toolOwnershipFailureText}
              EOF
                              exit 1
                            fi
                            touch "$out"
            '';

            catalogPolicy =
              let
                _ =
                  assert dotlib.hasHomebrewInstallPayload { casks = [ "keyclu" ]; };
                  assert (!dotlib.hasHomebrewInstallPayload { taps = [ "homebrew/cask" ]; });
                  assert lib.hasInfix "core.fakeTool" catalogValidationFailureText;
                  assert lib.hasInfix "darwin" catalogValidationFailureText;
                  assert brewNixOverlapReport.hasFailures;
                  assert lib.any
                    (message: lib.hasInfix "configured in both Homebrew and brew-nix" message)
                    brewNixOverlapReport.failureMessages;
                  assert lib.any
                    (entry: entry.itemType == "cask" && entry.itemName == "keyclu")
                    brewNixDuplicateClaimReport.duplicateHomebrewItems;
                  null;
              in
              builtins.seq _ (pkgs.runCommand "catalog-policy-check" { } ''
                touch "$out"
              '');
          };

          devShells.default = mkPortableDevShell {
            inherit pkgs;
            formatterWrapper = config.treefmt.build.wrapper;
          };

          packages = {
            darwin-rebuild = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild;
          };

          apps = {
            dotfiles = mkDotfilesApp {
              name = "cli";
              description = "Unified dotfiles CLI (apply/update/doctor/bootstrap/export-clean/list-tools/sync).";
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
            darwin-rebuild = {
              type = "app";
              program = "${inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild}/bin/darwin-rebuild";
              meta.description = "Pinned nix-darwin rebuild wrapper from this flake lock.";
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
            export-clean = mkDotfilesApp {
              name = "export-clean";
              subcommand = "export-clean";
              description = "Export a clean tracked copy without .git metadata or AppleDouble files.";
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
      } // linuxContributorOutputs // (if localStub then { } else {
        inherit nixosConfigurations homeConfigurations darwinConfigurations;
      });
    };
}

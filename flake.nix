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
      mkConfigurations = { moduleSystem, paths, exclude ? [ ] }:
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
          inherit paths exclude;
          extensions = with denix.lib.extensions; [
            args
            (base.withConfig { args.enable = true; })
          ];
          specialArgs = { inherit inputs; };
          # Import external modules
          extraModules =
            (if moduleSystem == "darwin" then [
              inputs.brew-nix.darwinModules.default
              inputs.mac-app-util.darwinModules.default
              inputs.nix-homebrew.darwinModules.nix-homebrew
            ] else [ ]);
        });

      mkLatestConfigurations = moduleSystem:
        mkConfigurations {
          inherit moduleSystem;
          paths = [ ./nix/denix ];
          exclude = [ ./nix/denix/lib/mk-darwin-host.nix ] ++ (
            if moduleSystem == "nixos" then
              [
                ./nix/denix/hosts/a2m_nixos
                ./nix/denix/hosts/a2m_mac
                ./nix/denix/hosts/mn_mac
                ./nix/denix/rices/full
                ./nix/denix/rices/mn
                ./nix/denix/rices/minimum
              ]
            else if moduleSystem == "darwin" then
              [ ./nix/denix/hosts/a2m_nixos ]
            else
              [ ]
          );
        };
    in
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.treefmt-nix.flakeModule ];
      systems = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];

      perSystem = { pkgs, config, ... }: {
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
              "''${files[@]}"
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
          update = {
            type = "app";
            program = "${./nix/scripts/update.sh}";
            meta.description = "Update flake inputs, run checks, and build host targets.";
          };
          list-tools = {
            type = "app";
            program = "${./nix/scripts/list-tools.sh}";
            meta.description = "List effective myconfig.tools values for a host/rice.";
          };
          apply = {
            type = "app";
            program = "${./nix/scripts/apply.sh}";
            meta.description = "Build or switch nix-darwin configurations.";
          };
          doctor = {
            type = "app";
            program = "${./nix/scripts/doctor.sh}";
            meta.description = "Run dotfiles health checks.";
          };
          bootstrap = {
            type = "app";
            program = "${./nix/scripts/bootstrap.sh}";
            meta.description = "Initialize local facts/secrets and optionally apply.";
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
            description = "Web development template: devShell with Node 22, pnpm, bun, wrangler, awscli2, jq/yq, mkcert, just; Prettier formatting via treefmt-nix; apps.dev/apps.format and checks";
          };
        };
      } // (if localStub then { } else {
        nixosConfigurations = mkLatestConfigurations "nixos";
        homeConfigurations = mkLatestConfigurations "home";
        darwinConfigurations = mkLatestConfigurations "darwin";
      });
    };
}

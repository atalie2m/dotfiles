{
  description = "Web dev template (Node22, pnpm, bun, wrangler, awscli2, jq/yq, mkcert, just) with formatters and checks";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };

  outputs = { self, nixpkgs, flake-parts, treefmt-nix, pre-commit-hooks, ... }@inputs:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = { pkgs, system, ... }: let
        node = pkgs.nodejs_22;
      in {
        devShells.default = pkgs.mkShell {
          name = "web-dev";
          packages = [
            node
            (pkgs.nodePackages.pnpm)
            pkgs.bun
            pkgs.wrangler
            pkgs.awscli2
            pkgs.jq
            pkgs.yq
            pkgs.mkcert
            pkgs.just
          ];
          shellHook = ''
            echo "web-dev shell: Node $(node -v), pnpm $(pnpm -v)"
          '';
        };

        # formatters bundled via treefmt
        treefmt = {
          programs = {
            prettier.enable = true;
          };
          settings = {
            formatter = {
              prettier = {
                includes = [ "**/*.{js,jsx,ts,tsx,css,md,json}" ];
              };
            };
          };
        };

        checks = {
          # Run treefmt via pre-commit using our wrapper (so Prettier integration works)
          pre-commit = pre-commit-hooks.lib.${system}.run {
            src = ./.;
            hooks.treefmt = {
              enable = true;
              package = self.formatter.${system};
            };
          };
          # Expose formatter as a check so `nix flake check` builds it too
          treefmt = self.formatter.${system};
        };

        apps = {
          dev = {
            type = "app";
            program = pkgs.writeShellScript "dev" ''
              set -euo pipefail
              if [ -f package.json ]; then
                if [ -f pnpm-lock.yaml ]; then pnpm install; elif [ -f bun.lockb ]; then bun install; else npm install; fi
              fi
              echo "Starting dev task..."
            '';
          };
          format = {
            type = "app";
            program = pkgs.writeShellScript "format" ''
              exec ${self.formatter.${system}}/bin/treefmt "$@"
            '';
          };
        };

        # expose treefmt as formatter
        formatter = treefmt-nix.lib.mkWrapper pkgs self.treefmt;
      };
    };
}



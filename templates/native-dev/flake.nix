{
  description = "C / C++ / Zig native application template";

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
      perSystem = { pkgs, config, lib, ... }: {
        devShells.default = pkgs.mkShell {
          name = "native-dev";
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
            cmake
            ninja
            meson
            pkg-config
            gcc
            clang
            llvm
            lld
            mold
            zig
            ccache
            sccache
            clang-tools
            include-what-you-use
            cppcheck
            cpplint
            cmake-format
            bear
            compiledb
            ccls
            gdb
            lldb
            hyperfine
            gtest
            catch2
            doctest
            criterion
            conan
            vcpkg
          ] ++ lib.optionals pkgs.stdenv.isDarwin [
            samply
          ] ++ lib.optionals pkgs.stdenv.isLinux [
            rr
            valgrind
            heaptrack
            linuxPackages.perf
            hotspot
          ];
          shellHook = ''
            ${config.pre-commit.installationScript}
            if [[ -z "''${ZSH_VERSION:-}" && $- == *i* ]]; then exec ${pkgs.zsh}/bin/zsh -i; fi
          '';
        };
        treefmt = { projectRootFile = "flake.nix"; programs = { clang-format.enable = true; nixpkgs-fmt.enable = true; shfmt.enable = true; taplo.enable = true; }; };
        pre-commit.settings.hooks = {
          clang-format.enable = true;
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

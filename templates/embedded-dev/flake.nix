{
  description = "Embedded / MCU / FPGA project template";

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
      perSystem = { pkgs, config, lib, ... }: {
        devShells.default = pkgs.mkShell {
          name = "embedded-dev";
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
            probe-rs-tools
            cargo-binutils
            cargo-generate
            flip-link
            elf2uf2-rs
            picotool
            gcc-arm-embedded
            openocd
            pyocd
            qemu
            tio
            minicom
            picocom
            dfu-util
            avrdude
            esptool
            espflash
            espup
            cmake
            ninja
            dtc
            rust-bindgen
            svd2rust
            verilator
            yosys
            nextpnr
            sby
            gtkwave
          ] ++ lib.optionals pkgs.stdenv.isLinux [
            renode
          ];
          shellHook = ''
            ${config.pre-commit.installationScript}
            if [[ -z "''${ZSH_VERSION:-}" && $- == *i* ]]; then exec ${pkgs.zsh}/bin/zsh -i; fi
          '';
        };
        treefmt = { projectRootFile = "flake.nix"; programs = { nixpkgs-fmt.enable = true; rustfmt.enable = true; shfmt.enable = true; taplo.enable = true; }; };
        pre-commit.settings.hooks = {
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
        apps.format = { type = "app"; program = "${config.treefmt.build.wrapper}/bin/treefmt"; };
        formatter = config.treefmt.build.wrapper;
      };
    };
}

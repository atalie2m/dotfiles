{ delib, ... }:

# Codex CLI overlay for Denix
delib.module {
  name = "packages.codex-overlay";

  # This module doesn't have user-facing options, it just provides the overlay
  options.packages.codex-overlay = with delib.options; {
    enable = boolOption false;
  };

  # Apply the overlay at both home and darwin levels
  home.ifEnabled = _: {
    nixpkgs.overlays = [
      (final: prev: {
        codex = prev.codex.overrideAttrs (old: rec {
          version = "0.16.0";
          src = prev.fetchFromGitHub {
            owner = "openai";
            repo = "codex";
            rev = "rust-v${version}";
            hash = "sha256-Lgf+s4BGFgfBDC1ZA9Wwqvf4n4fNGEmL+Ma0Fe9F8BI=";
          };
          # need update pnpmDeps
          pnpmDeps = prev.pnpm_10.fetchDeps {
            inherit (old) pname pnpmWorkspaces;
            inherit version src;
            fetcherVersion = 1;
            hash = "sha256-SyKP++eeOyoVBFscYi+Q7IxCphcEeYgpuAj70+aCdNA=";
          };
          # prevent version error
          doInstallCheck = false;
        });
      })
    ];
  };

  darwin.ifEnabled = _: {
    nixpkgs.overlays = [
      (final: prev: {
        codex = prev.codex.overrideAttrs (old: rec {
          version = "0.16.0";
          src = prev.fetchFromGitHub {
            owner = "openai";
            repo = "codex";
            rev = "rust-v${version}";
            hash = "sha256-Lgf+s4BGFgfBDC1ZA9Wwqvf4n4fNGEmL+Ma0Fe9F8BI=";
          };
          # need update pnpmDeps
          pnpmDeps = prev.pnpm_10.fetchDeps {
            inherit (old) pname pnpmWorkspaces;
            inherit version src;
            fetcherVersion = 1;
            hash = "sha256-SyKP++eeOyoVBFscYi+Q7IxCphcEeYgpuAj70+aCdNA=";
          };
          # prevent version error
          doInstallCheck = false;
        });
      })
    ];
  };
}

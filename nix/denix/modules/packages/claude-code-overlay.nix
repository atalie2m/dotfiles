{ delib, ... }:

let
  overlay = final: prev: {
    claude-code = prev.claude-code.overrideAttrs (old: rec {
      version = "2.0.67";
      src = prev.fetchzip {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-a1i8N6LZYA3XJx7AqDDOoyO5pf+t9WZ6vBQVZkUbpxM=";
      };

      nativeBuildInputs = (old.nativeBuildInputs or []) ++ [
        prev.nodejs_22
        prev.makeBinaryWrapper
      ];

      buildPhase = ''
        runHook preBuild
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        dest=$out/lib/node_modules/@anthropic-ai/claude-code
        mkdir -p "$dest"
        shopt -s dotglob
        cp -r ./* "$dest"
        shopt -u dotglob

        mkdir -p $out/bin
        makeBinaryWrapper ${prev.nodejs_22}/bin/node $out/bin/claude --add-flags "$dest/cli.js"

        runHook postInstall
      '';

      doInstallCheck = false;
    });
  };

in

# Claude Code overlay for Denix
delib.module {
  name = "packages.claude-code-overlay";

  # This module doesn't have user-facing options, it just provides the overlay
  options.packages.claude-code-overlay = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = _: {
    nixpkgs.overlays = [ overlay ];
  };

  darwin.ifEnabled = _: {
    nixpkgs.overlays = [ overlay ];
  };
}

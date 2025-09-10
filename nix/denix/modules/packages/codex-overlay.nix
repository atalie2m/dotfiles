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
          # Use the prebuilt NPM tarball published by @openai/codex
          version = "0.31.0";
          src = prev.fetchzip {
            url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
            hash = "sha256-4u7bFrdu8+rMQj1BLHOLLF6zwa43ayn2RqxOiOfMuDA=";
          };

          # Avoid pnpm hooks; only keep tools needed by installPhase
          nativeBuildInputs = with prev; [
            nodejs_22
            makeBinaryWrapper
            installShellFiles
          ];

          # No build step is required for the NPM tarball
          buildPhase = ''
            runHook preBuild
            runHook postBuild
          '';

          # Install from tarball contents and create node wrapper
          installPhase = ''
            runHook preInstall

            dest=$out/lib/node_modules/@openai/codex
            mkdir -p "$dest"
            cp -r bin package.json README.md "$dest"

            mkdir -p $out/bin
            makeBinaryWrapper ${prev.nodejs_22}/bin/node $out/bin/codex --add-flags "$dest/bin/codex.js"

            ${prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
              $out/bin/codex completion bash > codex.bash
              $out/bin/codex completion zsh > codex.zsh
              $out/bin/codex completion fish > codex.fish
              installShellCompletion codex.{bash,zsh,fish}
            ''}

            runHook postInstall
          '';

          # Avoid running install checks that assume a build from sources
          doInstallCheck = false;
        });
      })
    ];
  };

  darwin.ifEnabled = _: {
    nixpkgs.overlays = [
      (final: prev: {
        codex = prev.codex.overrideAttrs (old: rec {
          # Use the prebuilt NPM tarball published by @openai/codex
          version = "0.31.0";
          src = prev.fetchzip {
            url = "https://registry.npmjs.org/@openai/codex/-/codex-${version}.tgz";
            hash = "sha256-4u7bFrdu8+rMQj1BLHOLLF6zwa43ayn2RqxOiOfMuDA=";
          };

          # Avoid pnpm hooks; only keep tools needed by installPhase
          nativeBuildInputs = with prev; [
            nodejs_22
            makeBinaryWrapper
            installShellFiles
          ];

          # No build step is required for the NPM tarball
          buildPhase = ''
            runHook preBuild
            runHook postBuild
          '';

          # Install from tarball contents and create node wrapper
          installPhase = ''
            runHook preInstall

            dest=$out/lib/node_modules/@openai/codex
            mkdir -p "$dest"
            cp -r bin package.json README.md "$dest"

            mkdir -p $out/bin
            makeBinaryWrapper ${prev.nodejs_22}/bin/node $out/bin/codex --add-flags "$dest/bin/codex.js"

            ${prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
              $out/bin/codex completion bash > codex.bash
              $out/bin/codex completion zsh > codex.zsh
              $out/bin/codex completion fish > codex.fish
              installShellCompletion codex.{bash,zsh,fish}
            ''}

            runHook postInstall
          '';

          # Avoid running install checks that assume a build from sources
          doInstallCheck = false;
        });
      })
    ];
  };
}

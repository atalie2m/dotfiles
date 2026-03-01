# Homebrew Policy

This document defines package-source boundaries for this dotfiles flake.

## Source Boundary

1. Use Nix packages by default for CLI tools and libraries.
2. Use `tools.system.homebrewNative` only for software that is better managed as Homebrew formulas/casks on macOS (for example GUI apps that update rapidly or are macOS-specific).
3. Use `tools.system.brewNix` as a pinned/fallback mechanism when native Homebrew integration is unsuitable.
4. For Homebrew-only installs that need no extra behavior, add them to `nix/denix/modules/tools/brew-catalog.nix` instead of creating a dedicated module file.
5. Keep dedicated Homebrew modules only when additional configuration/activation logic is required.

## Duplication Rules

1. Do not install the same CLI from both Nix and Homebrew.
2. When migrating a tool source (Nix <-> Homebrew), remove the old declaration in the same change.
3. Keep GUI apps in Homebrew casks unless there is a strong reason to package them with Nix.

## PATH and Runtime Rules

1. Prefer Nix-provided CLIs in `PATH` for reproducibility.
2. If a Homebrew CLI must remain, document why in the module that enables it.
3. Validate the effective binary with `command -v <tool>` after apply/build changes.

## Review Checklist

1. Is each tool declared in exactly one source?
2. Is the source choice consistent with this policy?
3. Does `PATH` resolve to the intended executable?

## Tool-Specific Notes

1. Cloudflare `wrangler`: prefer Nix (`home-manager` or project `flake.nix`) as the default source.
2. Keep Homebrew `wrangler` only as a pending fallback when the Nix package is broken or lagging.

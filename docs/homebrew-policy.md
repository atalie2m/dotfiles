# Homebrew Policy

This document defines package-source boundaries for this dotfiles flake.

## Source Boundary

1. Use Nix packages by default for CLI tools and libraries.
2. Use Homebrew only for software that is macOS-specific or intentionally latest-first (typically GUI apps and a small number of fast-moving CLIs).
3. Route Homebrew installs through catalog-backed toggles under `myconfig.tools` whenever possible, not ad-hoc backend lists.
4. Register Homebrew ownership in `nix/catalog/tools/homebrew-ownership.nix`, including backend metadata for `homebrewNative` vs `brewNix`.
5. Use `tools.system.brewNix` only as an explicit alternative backend when native Homebrew integration is unsuitable; treat both backend surfaces as internal machinery rather than public configuration API.

## Duplication Rules

1. Do not install the same CLI from both Nix and Homebrew.
2. When migrating a tool source (Nix <-> Homebrew), remove the old declaration in the same change.
3. Keep GUI apps in Homebrew casks unless there is a strong reason to package them with Nix.
4. `flake check` validates final Darwin configs and fails if a Homebrew item is unregistered, claimed by multiple owners, overlaps with a `brew-nix` cask, or a `group.tool` key is claimed by multiple registries.

## PATH and Runtime Rules

1. Prefer Nix-provided CLIs in `PATH` for reproducibility.
2. If a Homebrew CLI must remain, document why in the module or catalog entry that enables it.
3. Validate the effective binary with `command -v <tool>` after apply/build changes.

## Review Checklist

1. Is each tool declared in exactly one source?
2. Is the source choice consistent with this policy?
3. Is the Homebrew item covered by the ownership registry?
4. Does `PATH` resolve to the intended executable?

## Tool-Specific Notes

1. Cloudflare `wrangler`: prefer Nix (`home-manager` or project `flake.nix`) as the default source.
2. Keep Homebrew `wrangler` only when Nix packaging is unusable for your workflow.

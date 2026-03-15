# nix/denix/lib

Shared helper functions for this repository's Denix modules.

Current helpers:

- `mk-darwin-host.nix`: shared host constructor for Darwin hosts.
- `mk-nixos-host.nix`: shared host constructor for NixOS hosts.
- `capability-bundles.nix`: reusable capability bundles imported by Denix rice definitions.
- `../../lib/default.nix`: shared `dotlib` helpers, including the canonical host model helpers.

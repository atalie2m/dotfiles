# nix/denix/lib

Shared helper functions for this repository's Denix modules.

Current helpers:

- `mk-darwin-host.nix`: shared host constructor for Darwin hosts.
- `mk-nixos-host.nix`: shared host constructor for NixOS hosts.
- `../../lib/default.nix`: shared `dotlib` helpers, including `mkHostContext` and `riceProfiles`.

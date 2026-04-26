[日本語版はこちら](ja/architecture-reset.md)

# Architecture Reset

This document explains the Darwin-only reset: what was removed, what became stricter, and what the repository now treats as its supported architecture.

## Goal

The reset intentionally narrowed the repository to one product:

- a Darwin-first personal system platform
- with explicit mutable surfaces
- and a typed Rust control plane

The point was not to hide mutable state. The point was to make ownership, orchestration, and host truth obvious.

## Design principles

- `One product, one operational API`: the supported operational root surface is Darwin-first.
- `Canonical host truth is shared`: modules consume `myconfig.hostContext.*`.
- `Typed truth beats ad-hoc validation`: machine metadata and host-derived data are normalized once.
- `Mutable boundaries stay explicit`: shell entrypoints, Doom Emacs config, VS Code profiles, and Homebrew/app state are reconciled surfaces, not fake-declarative state.
- `Shell is an adapter, not the control plane`: shell remains only as a thin entrypoint layer; orchestration lives in Rust.

## What changed

### Root flake scope

After the reset:

- the supported operational root surface is Darwin-first
- `darwinConfigurations` is always exported
- project `templates` remain the reusable public artifacts
- unsupported Home Manager/NixOS trees and Linux contributor outputs were removed

Intent:

- make the root flake look like the product it actually operates
- keep public evaluation stable even with placeholder public facts

### Facts and host model

After the reset:

- raw local facts remain input-only data
- canonical derived host data is built once from raw facts plus the host declaration
- modules read `myconfig.hostContext.*`
- machine metadata is typed instead of left as an unstructured blob

Intent:

- keep host identity and normalization in one place
- let Nix types carry more of the contract

### Platform truth

After the reset:

- host declarations provide `system` exactly once
- `os`, `arch`, default home directory, and related values derive from that system
- raw facts no longer own platform identity

Intent:

- keep machine identity a host concern
- stop letting modules discover platform truth from multiple places

### CLI and workspace boundaries

After the reset:

- Rust is a real workspace with `dotfiles-core`, `dotfiles-cli`, and `dotfiles-sync-vscode`
- `dotfiles-cli` owns `apply`, `update`, `doctor`, `bootstrap`, `export-clean`, `list-tools`, `matrix-tools`, and `sync`
- `dotfiles-sync-vscode` is packaged separately and invoked through `dotfiles`
- shell sync is implemented in Rust instead of Bash

Intent:

- keep bounded contexts readable from the workspace layout
- stop treating the VS Code engine crate as the physical home of the entire CLI

### Mutable surfaces

After the reset:

- `sync shell` reconciles writable shell entrypoints in Rust
- `sync emacs` reconciles writable Doom Emacs config files in Rust
- `sync neovim` reconciles writable Neovim config drift and effective Lazy lock state in Rust
- `scripts/sync.sh` is only a thin shell wrapper
- `sync vscode` dispatches to the dedicated `dotfiles-sync-vscode` binary
- Homebrew ownership remains declarative and validated, but runtime app state stays writable

Intent:

- preserve the explicit mutable-surface model
- move orchestration into typed code

### Bundle rollout policy

After the reset:

- tool groups remain taxonomy
- bundle membership is explicit in capability bundles
- new tools no longer roll out implicitly just because they were added under an enabled group

Intent:

- separate classification from rollout policy
- make host behavior changes explicit in rice composition

## Important repository facts

- the canonical host model lives at `myconfig.hostContext.*`
- `pro` now truly disables the VS Code module
- `partial` disables the VS Code module and activation sync, and only `codex` remains enabled among AI coding agents
- `tools.system.brewNix` no longer auto-enables `tools.system.macAppUtil`

## What did not change

- Denix remains the composition layer
- existing Darwin host names remain intact
- mutable surfaces remain mutable by design
- the Homebrew ownership registry remains the policy center

## Verification expectations

The intended verification path is:

- `cargo test` for the Rust workspace
- `nix flake check` with real local `facts` and `secrets`
- Darwin builds for touched hosts
- shell and VS Code smoke tests under the portable checks

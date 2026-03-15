# Architecture Reset

This document explains the recent architecture reset: what changed, what stayed the same, and why the repository now looks the way it does.

## Goal

The reset intentionally re-scoped the repository to one primary product:

- a Darwin-first personal system platform
- with in-repo runtime adapters for mutable surfaces

The intent was not to remove all complexity. The intent was to stop spreading the same truth across too many layers, shrink the public surface area, and make mutable boundaries explicit instead of implicit.

## Design Principles

- `One product, one primary API`: the supported operational root surface is Darwin-first.
- `Typed truth beats ad-hoc validation`: data that modules depend on should be derived once and reused.
- `Host declarations own platform`: the target system belongs to the host declaration, not to user facts.
- `Composition truth should live with composition`: Denix rices keep their names, but composition moved back into Denix-oriented data instead of a side table in `dotlib`.
- `Mutable boundaries stay explicit`: shell entrypoints, VS Code profile state, and Homebrew/macOS app state are reconciled surfaces, not fake-declarative ones.
- `Shell is an adapter, not the control plane`: shell remains for compatibility shims and OS-leaf behavior; orchestration lives in the typed Rust CLI.

## Before And After

### 1. Root flake scope

Before:

- the root flake mixed several bounded contexts: Darwin operation, Linux contributor support, templates, and extra output surfaces
- output shape changed depending on stubbed local inputs
- the day-to-day CLI had to defend itself against a wider API than it actually supported

After:

- the supported operational root surface is Darwin-first
- `templates.web-dev` remains the reusable public artifact
- `homeConfigurations` is no longer part of the root API, and `nixosConfigurations` is reduced to an empty compatibility attrset rather than an operational surface
- the operational CLI resolves `darwinConfigurations` only

Intent:

- make the root flake look like the thing it actually is in day-to-day use
- keep reusable/public artifacts small and stable

### 2. Facts and host model

Before:

- derived truth was split across raw `facts`, `constants`, host constructors, and a separate doctor schema
- required values were often represented by empty-string defaults and then rejected later
- modules could read both raw and derived values

After:

- raw local facts are input-only data
- canonical derived host data is built once from raw facts plus the host declaration
- modules read `myconfig.hostContext.*`
- bootstrap and doctor reuse the same canonical facts/schema source instead of maintaining parallel contracts

Intent:

- make the domain model explicit
- remove sentinel values and "validate later" behavior where Nix can express the contract directly

### 3. Platform truth

Before:

- platform/system truth was split between `facts.user.platform`, fallback constants, and runtime/platform checks
- modules could infer Darwin/Linux from different sources depending on which file you opened

After:

- host declarations provide `system` exactly once
- `os`, `arch`, default home directory, and related derived values flow from that system
- raw facts no longer accept `platform`, `systemType`, or `architecture`

Intent:

- make target identity a host concern instead of a user-facts concern
- stop letting multiple sources disagree about the same machine

### 4. Denix rice composition

Before:

- rice names existed in Denix, but the effective composition truth lived in `dotlib.riceProfiles`
- profile behavior was managed mainly as a feature-flag matrix

After:

- the current rice names remain unchanged
- Denix rice definitions import named capability bundles and small local overrides
- `dotlib.riceProfiles` is gone

Intent:

- keep composition truth where composition is declared
- preserve existing user-facing rice names while reducing indirection

### 5. Homebrew boundary

Before:

- Homebrew ownership was split across multiple registries/catalogs
- backend-specific lists were easy to treat as public configuration surface even though they were intended as internals

After:

- Homebrew ownership is unified in `nix/catalog/tools/homebrew-ownership.nix`
- backend metadata still exists, but as internal machinery
- checks validate duplicate claims, unregistered items, and overlap with `brew-nix`

Intent:

- keep the strong policy checks
- reduce the number of places that can claim authority over the same Homebrew item

### 6. CLI and orchestration

Before:

- Bash handled target parsing, input resolution, update flow, and build orchestration
- wrapper scripts had accumulated control-plane logic and test surface

After:

- the Rust `dotfiles` binary is the orchestration entrypoint
- `scripts/*.sh` are compatibility shims or adapter scripts
- portable checks inject the Rust CLI directly, so compatibility shims are tested in the same architecture they now use

Intent:

- move long-lived command semantics into typed code
- keep shell focused on compatibility and OS-leaf work

### 7. VS Code sync engine

Before:

- the VS Code engine depended on upstream internal storage shapes with most logic concentrated in a large `apply.rs`
- native checks were disabled in Nix packaging

After:

- the engine is split into bounded modules for profile registry, extension manifest handling, enablement DB, and planning
- fixture-style Rust tests run in Nix builds
- `doCheck = true` is enabled for the package

Intent:

- keep the subsystem in-repo for now, but make it behave like a real maintained subsystem instead of an untested utility

## Important Intentional Deviation

The original reset plan called for the canonical model to live at `myconfig.host.*`.

In this repository, the canonical model lives at `myconfig.hostContext.*` instead.

Reason:

- Denix already occupies `myconfig.host`
- reusing that path would have created option/declaration conflicts and made the model less explicit, not more

The important architectural change is not the exact name. The important change is that modules now share one canonical typed host model.

## What Did Not Change

- Denix remains the composition layer.
- Existing rice names remain intact.
- Mutable surfaces are still mutable by design.
- VS Code sync remains in this repository for now.

## Non-goals

- This reset did not try to make VS Code, shell entrypoints, or Homebrew fully immutable.
- This reset did not remove every compatibility surface immediately; existing shell entrypoints still exist as shims.
- This reset did not delete in-repo NixOS/Home Manager composition trees; it removed them from the supported operational root API.

## Verification

The reset was verified with:

- full `nix flake check` against real local `facts` and `secrets` inputs
- Darwin system builds for `pro_mac`, `ultra_mac`, and `minimal_mac`
- native Rust tests for the VS Code engine and Rust CLI
- shell and VS Code smoke/integration tests under the portable check suite

# Architecture

This repository keeps Denix orchestration, reusable modules, catalog data, and runtime scripts in separate trees so each layer can evolve independently.

For the before/after rationale behind the current shape, see [`docs/architecture-reset.md`](architecture-reset.md).

## Layout

- `nix/denix/{darwin,home,nixos}`: host and rice declarations only.
- `nix/denix/lib`: host constructors and Denix-specific helpers.
- `nix/modules/shared`: cross-cutting modules such as raw `facts`, canonical `host`, `system.nix`, and `nixpkgs.unfree`.
- `nix/modules/tools`: user-facing tool modules grouped by capability (`shell`, `editor`, `system`, `terminal`, etc.).
- `nix/catalog/tools`: declarative tool ownership data for Nixpkgs, catalog-backed Homebrew tools, and dedicated Homebrew-backed modules.
- `scripts/`: operational shell entrypoints, shared shell helpers, runtime adapters, and smoke/integration tests.
- `nix/scripts/`: Nix expressions used by the CLI, currently `list-tools.nix` and `doctor/facts-schema.nix`.
- `apps/`, `surfaces/`, and `keyboards/`: repo-managed assets consumed by modules and runtime scripts.

## Wiring Rules

- `flake.nix` passes `repoPaths` through `specialArgs`, and modules use that instead of deep relative imports.
- User-facing option paths stay under `myconfig.*`; directory moves should not rename options or hosts/rices.
- Runtime shell scripts live under `scripts/`; Nix expressions evaluated by those scripts stay under `nix/scripts/`.

## Practical Implications

- The operational CLI and supported root flake API are Darwin-first; in-repo NixOS/Home Manager trees remain for composition/reference, not as supported root outputs.
- If you add a reusable feature, put it in `nix/modules/` and keep `nix/denix/` focused on composition.
- If you add catalog-owned tools, update the relevant registry/catalog data under `nix/catalog/tools/` and the matching module/docs.
- If you add a new operational CLI behavior, implement it in the Rust `dotfiles` CLI and keep shell under `scripts/` as compatibility shims or OS-leaf adapters.

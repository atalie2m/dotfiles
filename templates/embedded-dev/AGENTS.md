# Repository Guidance

## Nix Flake Source Hygiene

This project is expected to be used as a Git flake. Contributors and coding agents must not run Nix with unfiltered local path flakes because `path:` references can copy the whole working tree into `/nix/store`, including large generated directories.

Do not run:

```sh
nix run path:$PWD#...
nix build path:$PWD#...
nix develop path:$PWD#...
nix flake check path:$PWD
```

Run from the repository root with Git flake refs instead:

```sh
nix run .#...
nix build .#...
nix develop
nix flake check
```

Initialize Git and keep generated directories ignored before using Nix. `target/`, `node_modules/`, `.git/`, and `.direnv/` must not be copied into the Nix flake source. If you add Nix packages or checks that consume local source, filter generated paths with `lib.cleanSourceWith`, `builtins.path`, `nix-gitignore`, or an equivalent structured source filter.

The template includes a source evaluation guard and `checks.flake-source-hygiene`; keep both enabled. They fail when those directories are present in the evaluated flake source.

## Cleanup

After an accidental unfiltered path-flake run, inspect collectable store paths first:

```sh
nix store gc --dry-run
```

Then delete old generations and collect garbage:

```sh
sudo nix-collect-garbage -d
```

Run the dry-run again to confirm the store is back under control.

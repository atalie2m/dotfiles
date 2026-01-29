# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Remarks
- Nix and Denix have few usage examples, so be sure to read the references carefully.
- `brew-nix` is different from `homebrew` (nix-darwin). `brew-nix` installs brew Casks without pre-installing Homebrew.
- Follow steps sequentially. After each step, run:
  - `git add` (stage changes)
  - `nix flake check --override-input local path:$HOME/.config/dotfiles-local --override-input secrets path:$HOME/.config/dotfiles-secrets`
  - `nix run .#apply -- --host <host> --action build`
  - Ask the user to run `nix run .#apply -- --host <host>` (or `sudo darwin-rebuild switch ...` if they prefer manual invocation)

## Build and Development Commands

### Build and Apply Configuration
```bash
# Build only
nix run .#apply -- --host a2m_mac --action build

# Switch to the new configuration (requires sudo; CLI handles it)
nix run .#apply -- --host a2m_mac

# Manual alternative
darwin-rebuild build --flake .#a2m_mac \
  --override-input local path:$HOME/.config/dotfiles-local \
  --override-input secrets path:$HOME/.config/dotfiles-secrets
```

## Architecture Overview

This is a **Nix flake-based dotfiles repository** using nix-darwin and Home Manager for macOS system configuration management.

### Core Structure
- **flake.nix**: Main flake definition with inputs (nixpkgs, nix-darwin, home-manager, brew-nix, sops-nix) and templates.
- **nix/denix/**: Denix hosts/modules/rices for system and user configuration.
- **nix/local/** and **nix/secrets/**: Stub inputs for public evaluation.
- **nix/scripts/**: CLI entrypoints (`apply`, `update`, `doctor`, `bootstrap`) and shared helpers.

### Local Facts + Secrets
- **Facts** live at `~/.config/dotfiles-local/facts.nix` and are injected with `--override-input local`.
- **Secrets** live at `~/.config/dotfiles-secrets/` and are injected with `--override-input secrets`.
- The repo contains stub inputs so templates work without local overrides; real configs require overrides.
  - The CLI apps (`apply/update/doctor/bootstrap`) pass these overrides automatically.

### Configuration Flow
1. `flake.nix` loads local inputs and gates `darwinConfigurations`/`homeConfigurations` when stubs are present.
2. **Denix hosts** read `inputs.local/facts.nix` and populate `config.facts`.
3. **Denix modules** consume `config.facts` (e.g., Git user info via constants).
4. **sops-nix** materializes secrets defined in `inputs.secrets/secrets.nix` at activation time.

-------
## Useful reference
### official documents
#### brew-nix
https://github.com/BatteredBunny/brew-nix
https://apribase.net/2025/03/24/brew-nix/

#### Denix
https://yunfachi.github.io/denix/getting_started/introduction
https://yunfachi.github.io/denix/getting_started/initialization
https://yunfachi.github.io/denix/getting_started/first_modules
https://yunfachi.github.io/denix/getting_started/transfer_to_denix
https://yunfachi.github.io/denix/modules/introduction-nixos
https://yunfachi.github.io/denix/modules/introduction
https://yunfachi.github.io/denix/modules/structure
https://yunfachi.github.io/denix/modules/examples
https://yunfachi.github.io/denix/options/introduction
https://yunfachi.github.io/denix/hosts/introduction
https://yunfachi.github.io/denix/hosts/structure
https://yunfachi.github.io/denix/hosts/examples
https://yunfachi.github.io/denix/configurations/introduction
https://yunfachi.github.io/denix/configurations/structure
https://yunfachi.github.io/denix/extensions/introduction
https://yunfachi.github.io/denix/extensions/structure
https://yunfachi.github.io/denix/extensions/development
https://yunfachi.github.io/denix/extensions/all-extensions
https://yunfachi.github.io/denix/rices/introduction
https://yunfachi.github.io/denix/rices/structure
https://yunfachi.github.io/denix/rices/examples
https://yunfachi.github.io/denix/troubleshooting
https://yunfachi.github.io/denix/showcase

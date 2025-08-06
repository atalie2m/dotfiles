# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Remarks
- Nix and Denix have few usage examples, so be sure to read the reference carefully.
- There is a nix expression called `brew-nix`. It is different from `homebrew`, which is based on `nix-darwin`. `brew-nix` allows you to install brew Cask without pre-installing `homebrew`.
- Follow the steps step by step.
    - After each step, do the following:
    - git add (be staging)
    - nix flake check
    - darwin-rebuild build --flake .#<write the value of `derib.host.name` in this repos here, such as common>
    - Ask the user to run `sudo darwin-rebuild switch --flake .`
## Build and Development Commands

### Build and Apply Configuration
```bash
# Build the configuration
darwin-rebuild build --flake .

# Switch to the new configuration (requires sudo)
sudo darwin-rebuild switch --flake .
```

### Git Filter Setup
The repository uses Git filters for system information abstraction. On a new clone, run:
```bash
git config filter.system-info.clean './.git-filters/clean.sh'
git config filter.system-info.smudge './.git-filters/smudge.sh'
```

## Architecture Overview

This is a **Nix flake-based dotfiles repository** using nix-darwin and Home Manager for macOS system configuration management.

### Core Structure
- **flake.nix**: Main flake definition with inputs (nixpkgs, nix-darwin, home-manager, brew-nix)
- **nix/env.nix**: Essential environment variables (username, paths, versions) - NOT for Denix configuration
- **nix/parts/default.nix**: Flake parts configuration that auto-generates darwin/home configurations from env.nix

### Key Components
- **System Layer**: nix-darwin configurations via Denix hosts in `nix/denix/hosts/`
- **User Layer**: Home Manager configurations via Denix modules in `nix/denix/modules/`
- **Package Management**: Nix packages + Homebrew integration via brew-nix
- **Multi-Host Support**: Automatically generates configurations for all hosts defined in env.nix

### Git Filter System
Uses custom Git filters (`.git-filters/`) to abstract system-specific information:
- **clean.sh**: Converts system info to placeholders on `git add`
- **smudge.sh**: Replaces placeholders with actual values on `git checkout`
- Handles: ComputerName, LocalHostName, UserName, and home directory paths

### Module Organization
- `nix/denix/hosts/`: Host definitions and system-level settings
- `nix/denix/modules/`: Modular user and system configuration
- `nix/denix/rices/`: Reusable configuration bundles

### env.nix Purpose and Scope
**IMPORTANT**: `nix/env.nix` is specifically designed to contain ONLY essential environment variables that Nix requires, such as:
- User information (username, email, fullName)
- System information (architecture, platform, stateVersion)
- Essential paths (homeDirectory, dotfilesPath)

**What does NOT belong in env.nix**:
- Denix host configurations (belong in `nix/denix/hosts/`)
- Denix module settings (belong in `nix/denix/modules/`)
- Denix rice configurations (belong in `nix/denix/rices/`)
- Feature flags, application preferences, or complex configuration logic

env.nix serves as a centralized source of truth for system-specific values that need to be referenced across the entire configuration, replacing hardcoded placeholders while maintaining Nix's functional purity.

### Configuration Flow
1. **env.nix** provides essential environment variables (username, paths, versions)
2. **parts/default.nix** auto-generates darwinConfigurations and homeConfigurations
3. **Denix hosts** in `nix/denix/hosts/` define system-level settings and reference env.nix for user info
4. **Denix modules** in `nix/denix/modules/` provide modular configuration components
5. **Denix rices** in `nix/denix/rices/` bundle related configurations
6. Git filters ensure configurations remain portable across different machines



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

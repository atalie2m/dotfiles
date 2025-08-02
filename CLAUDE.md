# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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
- **nix/env.nix**: Centralized host configuration and defaults
- **nix/parts/default.nix**: Flake parts configuration that auto-generates darwin/home configurations from env.nix

### Key Components
- **System Layer**: nix-darwin configurations in `nix/modules/darwin/` and `nix/hosts/darwin/standard/`
- **User Layer**: Home Manager configurations in `nix/modules/home/`
- **Package Management**: Nix packages + Homebrew integration via brew-nix
- **Multi-Host Support**: Automatically generates configurations for all hosts defined in env.nix

### Git Filter System
Uses custom Git filters (`.git-filters/`) to abstract system-specific information:
- **clean.sh**: Converts system info to placeholders on `git add`
- **smudge.sh**: Replaces placeholders with actual values on `git checkout`
- Handles: ComputerName, LocalHostName, UserName, and home directory paths

### Module Organization
- `nix/modules/darwin/`: System-level macOS settings
- `nix/modules/home/`: User-level configurations via Home Manager
- `nix/modules/homebrew/`: Homebrew package management integration
- `nix/modules/nixpkgs/`: Package overlays and unfree package configuration

### Configuration Flow
1. **env.nix** defines hosts and their properties
2. **parts/default.nix** auto-generates darwinConfigurations and homeConfigurations
3. Each host gets both system (darwin) and user (home-manager) configurations
4. Git filters ensure configurations remain portable across different machines

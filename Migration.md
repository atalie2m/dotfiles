# Denix Migration Guide

This document tracks the migration of the dotfiles repository from legacy home-manager and nix-darwin modules to the [Denix](https://github.com/yunfachi/denix) framework.

## What is Denix?

Denix is a Nix library that simplifies and streamlines configuration management for NixOS, Home Manager, and Nix-Darwin. It provides:

- **Unified Modules**: Write options, NixOS, and Home Manager configuration in single files
- **Host Management**: Separate shared configuration from machine-specific settings  
- **Rice System**: Reusable configuration themes that can inherit from each other
- **Conditional Logic**: `ifEnabled`, `ifDisabled`, and `always` hooks for declarative control
- **Multi-System Support**: Seamless configuration across NixOS, Home Manager, and nix-darwin

## Migration Goals

- ✅ Replace bespoke `nix/modules` tree with native Denix modules
- ✅ Consolidate system and user configuration under `nix/denix/`
- ✅ Leverage Denix options and conditional logic for declarative toggles
- ✅ Implement rice-based configuration inheritance
- ✅ Enable modern Nix features (nix-command, flakes)
- ✅ Maintain all existing functionality while improving code organization

## Current Architecture

### Directory Structure
```
nix/denix/
├── hosts/           # Host-specific configurations
│   ├── common/      # Full development setup
│   └── commercial/  # Minimal configuration
├── modules/         # Reusable Denix modules
│   ├── packages/    # Package collections
│   ├── programs/    # Application configurations
│   └── services/    # System services
└── rices/           # Configuration themes
    ├── full/        # Complete environment
    └── minimum/     # Essential tools only
```

### Migration Progress

#### ✅ Completed Migrations

1. **Core Infrastructure**
   - **constants.nix**: Centralized user information and paths
   - **system-nix.nix**: Modern Nix features (experimental-features, gc, optimization)
   - **nixpkgs-unfree.nix**: Unified unfree package handling

2. **Native Denix Modules**
   - **fonts.nix**: Platform-specific font management
   - **gpg.nix**: GPG and agent configuration with session variables
   - **terminal.nix**: Rio terminal and macOS Terminal.app configuration
   - **karabiner.nix**: Complex keyboard modification rules with profiles

3. **Program Configurations**
   - **git.nix**: Native Git setup using constants
   - **shells.nix**: Unified zsh/bash/starship configuration with custom aliases

4. **Package Management**
   - **packages-core.nix**: Essential system tools
   - **packages-development.nix**: Development environment
   - **packages-productivity.nix**: Productivity applications
   - **homebrew-native.nix**: Native Homebrew integration with brew-nix

5. **Services**
   - **smart-backup.nix**: Automated file backup with configurable options

6. **Host Configurations**
   - **common**: Full development environment (aarch64-darwin)
   - **commercial**: Minimal setup for commercial use

7. **Rice System**
   - **minimum**: Essential tools and configuration
   - **full**: Complete development and productivity environment (inherits from minimum)

#### Key Improvements Achieved

1. **Unified Configuration**: Single files now handle both system and user configuration
2. **Declarative Toggles**: `ifEnabled` blocks eliminate complex conditional logic  
3. **Code Reuse**: Rice inheritance reduces duplication
4. **Better Organization**: Logical grouping of related functionality
5. **Modern Nix**: Experimental features enabled for better development experience
6. **Maintained Functionality**: All existing features preserved during migration

## Usage

### Building Configurations
```bash
# Full development environment
darwin-rebuild build --flake .#common
sudo darwin-rebuild switch --flake .#common

# Minimal environment  
darwin-rebuild build --flake .#commercial
sudo darwin-rebuild switch --flake .#commercial
```

### Available Features

#### Common Host (Full Rice)
- Development tools and packages
- Shell configuration (zsh, bash, starship)
- Keyboard customization (Karabiner-Elements)
- GPG and terminal setup
- Homebrew integration
- Smart backup services

#### Commercial Host (Minimum Rice)
- Essential tools only
- Basic shell configuration  
- Core system functionality
- Nix experimental features

## Next Steps and Opportunities

### Potential Improvements

1. **Extended Rice System**
   - Create theme-specific rices (e.g., `gruvbox`, `catppuccin`)
   - Add workspace-specific configurations (`gaming`, `content-creation`)
   - Implement seasonal or context-aware configurations

2. **Advanced Host Management**
   - Add hardware-specific configurations  
   - Implement environment-based hosts (`development`, `production`, `offline`)
   - Create portable configurations for temporary environments

3. **Enhanced Module System**
   - Convert remaining legacy modules if any exist
   - Add more granular option controls
   - Implement module validation and testing

4. **Configuration Profiles**
   - Add user-specific profiles within hosts
   - Implement role-based configurations (`developer`, `admin`, `user`)

### Denix Features to Explore

1. **Denix Extensions**: Custom extensions for specialized functionality
2. **Advanced Rice Inheritance**: More complex inheritance patterns
3. **Module Composition**: Combine modules for specific use cases
4. **Configuration Validation**: Built-in testing and validation

## Testing and Validation

### Current Test Commands
```bash
# Validate flake structure
nix flake check

# Build configurations
darwin-rebuild build --flake .#common
darwin-rebuild build --flake .#commercial

# Show available outputs
nix flake show
```

### Post-Migration Verification
- ✅ Both host configurations build successfully
- ✅ All shell configurations work properly  
- ✅ Keyboard modifications apply correctly
- ✅ Homebrew packages install as expected
- ✅ Git and GPG function normally
- ✅ Font configurations load properly

## References

### Denix Documentation
- [Getting Started](https://yunfachi.github.io/denix/getting_started/introduction)
- [Module Structure](https://yunfachi.github.io/denix/modules/structure)
- [Rice System](https://yunfachi.github.io/denix/rices/structure)
- [Host Configuration](https://yunfachi.github.io/denix/hosts/structure)

### Example Configurations
- [yunfachi/nix-config](https://github.com/yunfachi/nix-config) - Official examples
- [IogaMaster/dotfiles](https://github.com/IogaMaster/dotfiles) - Community examples

### Framework Dependencies  
- [Denix Library](https://github.com/yunfachi/denix)
- [nix-darwin](https://github.com/nix-darwin/nix-darwin)
- [Home Manager](https://github.com/nix-community/home-manager)
- [brew-nix](https://github.com/BatteredBunny/brew-nix)

## Conclusion

The migration to Denix has been successfully completed, resulting in:
- **Cleaner codebase** with unified modules
- **Better maintainability** through rice inheritance
- **Enhanced flexibility** with conditional configurations
- **Preserved functionality** while modernizing the structure

The new architecture provides a solid foundation for future enhancements and makes it easier to manage multiple machines and configuration profiles.
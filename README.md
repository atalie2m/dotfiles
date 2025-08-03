# dotfiles

## Prerequisites
- Nix(Lix or Determinate's vanilla)

## Terminal Compatibility

**For macOS users**: Please use a 24-bit True Color compatible terminal instead of the default Terminal.app. The Starship prompt configuration in this repository uses True Color (#RRGGBB) values that are only properly displayed in terminals with full color support.

**Recommended terminals:**
- VS Code integrated terminal
- iTerm2
- Rio
- Kitty
- Alacritty

**Why this matters**: macOS Terminal.app only supports 256-color palette, which causes the Starship prompt colors to be approximated and appear different from the intended design. True Color terminals can display the full 16.7 million color spectrum, ensuring consistent visual appearance.

## Git Smudge/Clean Filters

Automatically handles system information abstraction in configurations using Git filters.

### Mechanism

- **clean.sh**: Executed on `git add` - converts actual system information to specific placeholders
- **smudge.sh**: Executed on `git checkout` - replaces placeholders with corresponding system values

### System Information Detection

**clean.sh** handles multiple system information formats:
- `ComputerName`: `John's Mac` → `{{COMPUTER_NAME}}` → `John's Mac`
- `ComputerName (serialized)`: `John's Mac` → `{{SERIALIZED_COMPUTER_NAME}}` → `Johns-Mac`
- `LocalHostName`: `Johns-Mac` → `{{LOCAL_HOSTNAME}}` → `Johns-Mac`
- `UserName`: `john` → `{{USER_NAME}}` → `john`

**smudge.sh** replaces each placeholder with its corresponding value.

### Workflow

```bash
# Working directory: darwinConfigurations."Johns-Mac"
# Working directory: primaryUser = "john";
git add flake.nix nix/nix-darwin.nix
# Repository: darwinConfigurations."{{LOCAL_HOSTNAME}}"
# Repository: primaryUser = "{{USER_NAME}}";

git checkout HEAD -- flake.nix nix/nix-darwin.nix
# Working directory: darwinConfigurations."Johns-Mac"
# Working directory: primaryUser = "john";
```

### Configuration

`.gitattributes`:
```
# Apply system-info filter to all text files that might contain system information
*.nix filter=system-info
*.txt filter=system-info
*.yaml filter=system-info
*.yml filter=system-info
*.json filter=system-info
*.toml filter=system-info
*.sh filter=system-info

# Exclude documentation files to keep examples stable
# README.md - keep examples as-is for documentation purposes

# Always apply to git-filters directory itself
.git-filters/* filter=system-info
```

Git setup (run once per repository):
```bash
git config filter.system-info.clean './.git-filters/clean.sh'
git config filter.system-info.smudge './.git-filters/smudge.sh'
```

**Note**: Git filter configuration is stored locally and needs to be set up on each machine/clone.

## Karabiner-Elements Setup

This repository includes comprehensive keyboard layouts and input method configurations for Karabiner-Elements in the `keyboards/karabiner/complex_modifications/` directory.

### Available Configurations

1. **japanese-input-toggle.json**: Japanese input method switching configurations
   - Command/Control/Option/Shift keys for 英数・かな switching
   - Caps Lock toggle functionality
   - Vim-friendly ESC key behavior
   - Based on KE-complex_modifications

2. **spacebar-to-shift.json**: Space-and-Shift (SandS) functionality
   - Spacebar acts as Left Shift when held with other keys
   - Normal space character when pressed alone
   - Based on KE-complex_modifications

3. **vylet-alt-layout.json**: Vylet alternative keyboard layout
   - Complete keyboard layout remapping
   - Created by MightyAcas
   - Optimized for efficient typing

4. **shingeta_en.json**: 新下駄配列 (Shingeta layout) for English typing games
   - Japanese keyboard layout optimized for typing games
   - Created by kouy, implemented by funatsufumiya

5. **shingeta_jp.json**: 新下駄配列 (Shingeta layout) for Japanese input
   - Full Japanese input support
   - Same layout as above but for general Japanese typing

### Manual Setup

To use the keyboard configurations from this dotfiles repository:

1. Create the Karabiner-Elements configuration directory:
   ```bash
   mkdir -p ~/.config/karabiner/assets/complex_modifications
   ```

2. Create symbolic links to the JSON files in your dotfiles:
   ```bash
   # Replace /path/to/your/dotfiles with your actual dotfiles path
   DOTFILES_PATH="/path/to/your/dotfiles"

   # Link all JSON files
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/japanese-input-toggle.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/spacebar-to-shift.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/vylet-alt-layout.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/shingeta/shingeta_en.json" ~/.config/karabiner/assets/complex_modifications/
   ln -sf "$DOTFILES_PATH/keyboards/karabiner/complex_modifications/shingeta/shingeta_jp.json" ~/.config/karabiner/assets/complex_modifications/
   ```

3. Restart Karabiner-Elements or go to Settings > Complex Modifications to see the new configurations.

4. Enable the desired rules in Karabiner-Elements Settings > Complex Modifications > Add rule.


**Note**: Karabiner-Elements only reads JSON files directly from the `complex_modifications` directory and does not recursively search subdirectories. The symbolic links allow you to keep your configurations organized in your dotfiles while making them available to Karabiner-Elements.

### Credits

These configurations are based on or include work from:
- **KE-complex_modifications** (Unlicense)
- **Shingeta Layout** by kouy and funatsufumiya (MIT License)
- **Vylet Keyboard Layout** by MightyAcas

See the LICENSE file for complete attribution information.

## Build darwin flake using:
```bash
# Build the configuration
darwin-rebuild build --flake .

# Switch to the new configuration
sudo darwin-rebuild switch --flake .
```

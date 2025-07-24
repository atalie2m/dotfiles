# dotfiles

## Prerequisites
- Nix(Lix or Determinate's vanilla)

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

## Build darwin flake using:
```bash
# Build the configuration
darwin-rebuild build --flake .

# Switch to the new configuration
sudo darwin-rebuild switch --flake .
```

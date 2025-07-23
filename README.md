# dotfiles

## Prerequisites
- Nix(Lix or Determinate's vanilla)

## Git Smudge/Clean Filters

Automatically handles hostname abstraction in nix-darwin configurations using Git filters.

### Mechanism

- **clean.sh**: Executed on `git add` - converts actual hostnames to specific placeholders
- **smudge.sh**: Executed on `git checkout` - replaces placeholders with corresponding system values

### Hostname Detection

**clean.sh** handles three macOS hostname formats:
- `ComputerName`: `Jhon's Mac` → `{{COMPUTER_NAME}}` → `Jhon's Mac`
- `ComputerName (serialized)`: `Jhon's Mac` → `{{SERIALIZED_COMPUTER_NAME}}` → `Jhon's-Mac`
- `LocalHostName`: `Jhons-Mac` → `{{LOCAL_HOSTNAME}}` → `Jhons-Mac`

**smudge.sh** replaces each placeholder with its corresponding value.

### Workflow

```bash
# Working directory: darwinConfigurations."u1s-MacBook-Air"
git add flake.nix
# Repository: darwinConfigurations."{{LOCAL_HOSTNAME}}"

git checkout HEAD -- flake.nix
# Working directory: darwinConfigurations."u1s-MacBook-Air"
```

### Configuration

`.gitattributes`:
```
flake.nix filter=hostname
.git-filters/* filter=hostname
```

Git setup (run once per repository):
```bash
git config filter.hostname.clean './.git-filters/clean.sh'
git config filter.hostname.smudge './.git-filters/smudge.sh'
```

**Note**: Git filter configuration is stored locally and needs to be set up on each machine/clone.

## Build darwin flake using:
```bash
# Build the configuration
darwin-rebuild build --flake .

# Switch to the new configuration
sudo darwin-rebuild switch --flake .
```

# Codex Homebrew Cask Hangs on macOS 26

Date: 2026-05-15

## Summary

The standalone Codex CLI installed by the official Homebrew cask can hang before
printing any output on macOS 26 when executed through the Caskroom-linked
`/opt/homebrew/bin/codex` path.

This is not only a local dotfiles ownership problem. Similar symptoms are
tracked upstream:

- [openai/codex#17447](https://github.com/openai/codex/issues/17447):
  Homebrew cask binary hangs at `_dyld_start` on macOS 26.4.1.
- [openai/codex#20025](https://github.com/openai/codex/issues/20025):
  Homebrew cask `codex` hangs, including `codex --version`.
- [openai/codex#5787](https://github.com/openai/codex/issues/5787):
  older quarantine/provenance failure on macOS 15.7.1.
- [Homebrew/homebrew-cask#170345](https://github.com/Homebrew/homebrew-cask/issues/170345):
  Homebrew discussion showing that cask-level quarantine bypass is not a
  durable Homebrew-managed state.

## Local Observation

Observed on:

- macOS: `26.5` (`25F71`)
- Homebrew cask: `codex 0.130.0`
- Official cask binary:
  `/opt/homebrew/Caskroom/codex/0.130.0/codex-aarch64-apple-darwin`
- Original link shape:
  `/opt/homebrew/bin/codex -> /opt/homebrew/Caskroom/codex/0.130.0/codex-aarch64-apple-darwin`

Symptoms:

- `codex --version` through `/opt/homebrew/bin/codex` hung and produced no
  output.
- `sample` showed the process stuck at `_dyld_start`.
- The Caskroom binary carried `com.apple.provenance`; `com.apple.quarantine`
  also appeared after cask reinstall.
- `xattr -dr com.apple.quarantine` was not enough.
- `xattr -c` did not remove `com.apple.provenance` from the Caskroom path.
- Copying the same bytes to another executable path made `codex --version`
  return.
- The Codex.app bundled CLI at
  `/Applications/Codex.app/Contents/Resources/codex` returned immediately.

The important local discriminator was path-sensitive behavior: the same binary
content worked when exposed as a regular executable copy under
`/opt/homebrew/bin`, but hung when reached through the Caskroom path.

## Dotfiles Contract

The public/default dotfiles contract remains the standard Homebrew cask:

```nix
casks = [ "codex" ];
```

The workaround is host-local, opt-in state. It is enabled only via local facts:

```nix
machines.own_mac.extra.codex.homebrewBinCopyWorkaround = true;
```

When that fact is true, `nix/flake/configurations.nix` adds a per-cask
`postinstall` that keeps the Homebrew cask as the source of truth but replaces
`/opt/homebrew/bin/codex` with a bin-local executable copy from the cask payload.

This is intentionally not the general catalog default. It is a local workaround
for a macOS/Homebrew/Codex release-path issue.

## Operational Guidance

Use dotfiles activation for managed Homebrew updates:

```bash
nix run .#apply -- --host own_mac
```

Avoid using standalone `brew upgrade --cask codex` as the normal path on hosts
that need the workaround. A plain cask upgrade can restore Homebrew's default
Caskroom symlink shape without running the dotfiles-specific host-local
postinstall.

Build-only commands do not repair the live Homebrew executable:

```bash
nix run .#apply -- --host own_mac --action build
```

## Triage Commands

Use these to confirm whether the problem is present:

```bash
sw_vers
brew list --cask --versions | rg -i '^codex|codex-fixed'
which -a codex
ls -l /opt/homebrew/bin/codex
xattr -lr /opt/homebrew/Caskroom/codex /opt/homebrew/bin/codex
codex --version
```

If `codex --version` hangs, sample it from another terminal:

```bash
pgrep -af 'codex-aarch64|/opt/homebrew/bin/codex|codex --version'
sample <pid> 3 -file /private/tmp/codex-hang.sample.txt
```

A `_dyld_start` sample with no user-code frames is strong evidence that this is
the upstream class tracked in the linked issues.

## Temporary Recovery

For this host, dotfiles activation should recreate the bin-local copy when the
local fact is enabled:

```bash
nix run .#apply -- --host own_mac
codex --version
```

The manual shape of the workaround is:

```bash
prefix=$(brew --prefix)
binary=$(/usr/bin/find "$prefix/Caskroom/codex" -type f -name 'codex-*apple-darwin' -print -quit)
/bin/rm -f "$prefix/bin/codex"
/usr/bin/install -m 0755 "$binary" "$prefix/bin/codex"
/usr/bin/xattr -c "$prefix/bin/codex" 2>/dev/null || true
```

Prefer the dotfiles activation path so the local workaround remains documented
and reproducible.

## Removal Criteria

Remove the local workaround and return this host to the plain cask when all of
these are true:

1. The official Homebrew cask executable at `/opt/homebrew/bin/codex` is again a
   cask-managed symlink or launcher.
2. `codex --version` returns promptly after `brew reinstall --cask codex`.
3. `sample` is no longer needed because startup reaches normal output.
4. The relevant upstream Codex issue has a release-side fix or the behavior no
   longer reproduces on this macOS release.

At that point, remove the local fact:

```nix
machines.own_mac.extra.codex.homebrewBinCopyWorkaround = true;
```

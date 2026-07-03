# Linux Dev Workbench Home Manager Target

Date: 2026-07-03

## Summary

Add a Linux/Home Manager target for the shared development workbench LXC managed
by `domus-ops`.

The target should reuse the existing dotfiles tool catalog and shell/editor
modules where they are portable, but it must not turn the repository into a
Linux host-infrastructure owner. `domus-ops` remains responsible for the LXC,
storage, Tailscale, SSH, observability, and host lifecycle. This repository
should own only the interactive user environment inside the workbench.

## Current Context

The live workbench is a Debian LXC on Proxmox with SSD-backed root storage and an
HDD-backed bulk mount. It is intended for both human and coding-agent work.

Important boundary:

- `domus-ops` declares and applies the LXC.
- `dotfiles` declares userland tools and shell/editor configuration.
- Project repositories keep language/runtime toolchains in their own flakes or
  dev shells.

Do not migrate the LXC substrate, Tailscale join, SSH access model, or
observability wiring into this repository.

## Host And User Identity Boundary

Be careful with user names and host names. This repository intentionally uses a
local facts plus host-model boundary:

- Raw machine-specific values live outside Git in the `local` input, typically
  `~/.config/dotfiles/facts.nix`.
- Host declarations provide stable target keys and system metadata.
- The canonical identity exposed to modules is `config.myconfig.hostContext`.
- Modules should read `myconfig.hostContext.*`, not raw facts.
- New direct reads of `inputs.local/facts.nix` should stay limited to the
  existing host-model/bootstrap boundary.

For the Linux target, do not hard-code a Unix user name, home directory, or live
hostname directly into modules. Add a stable dotfiles target key and derive the
runtime user, home directory, and machine values through the existing host model.

The target key does not have to equal the live system hostname. If the live
hostname changes, the dotfiles target should keep evaluating as long as the
local facts map the target key to the desired machine values.

## Desired End State

Expose a Home Manager configuration such as:

```text
homeConfigurations.<linux-workbench-target>
```

The exact target name should follow the repository's host target conventions,
but it should be distinct from Darwin host targets like `own_mac` and
`work_mac`.

The Linux target should support at least:

- a minimal profile with Git, shell basics, core navigation/search tools, and
  Nix helpers;
- a fuller workbench profile with tmux, Neovim, direnv, SOPS/age helpers, GitHub
  CLI, and common repository inspection tools;
- Linux-only package filtering through the existing catalog `systems` support;
- no Homebrew, nix-darwin, macOS UI, keyboard, or app-bundle management;
- no global Node.js, Go, Terraform, or OpenTofu host toggle.

Codex CLI should remain outside Nix package management for this target. The
workbench uses the official standalone installer so the CLI can track the
current upstream release. Dotfiles may provide checks, documentation, or an
update helper, but should not pin Codex CLI through Nix.

## Implementation Plan

1. Split the current Darwin-only flake outputs from portable Home Manager
   outputs.

   Keep `darwinConfigurations` unchanged for existing Mac hosts. Add Linux
   Home Manager outputs alongside them instead of replacing the Darwin root API.

2. Add a Linux host catalog.

   Prefer a new catalog path such as:

   ```text
   nix/catalog/linux/hosts.nix
   nix/catalog/linux/profiles.nix
   nix/catalog/linux/default.nix
   ```

   Reuse the existing profile vocabulary where useful, but do not reuse the
   `work_mac` policy model. The workbench is not a company-work-host policy
   target; it is a shared lab development node.

3. Extend host-model use without bypassing facts.

   Build the Linux host model from:

   - stable dotfiles host target key;
   - `machineKey`;
   - `system = "x86_64-linux"`;
   - local facts for user and machine details.

   Use `dotlib.buildHostModel` or a small generalized wrapper. Do not introduce
   ad hoc username or hostname literals in individual modules.

4. Add a Home Manager system builder.

   Use `inputs.home-manager.lib.homeManagerConfiguration` for Linux and import
   only portable modules:

   - shared host/profile/Nixpkgs policy modules;
   - shell modules;
   - Git/dev/core/catalog modules;
   - terminal/editor modules that work on Linux;
   - SOPS/age helpers where they do not assume macOS paths.

   Avoid importing Darwin-only modules:

   - `nix-darwin`;
   - Homebrew and brew-nix;
   - macOS UI/system naming;
   - Karabiner;
   - app bundle linking/copying.

5. Define the first workbench profile.

   Start conservatively:

   ```text
   core.enable = true
   dev.git / gh / shellcheck / shfmt / yamllint as needed
   shell.zsh or bash according to existing module support
   shell.direnv = true
   terminal.tmux = true
   editor.neovim = true
   security.sops = true
   network.mosh optional
   ```

   Keep language and IaC toolchains project-scoped. Do not add global Node.js,
   Go, Terraform, or OpenTofu toggles for this host.

6. Add Linux-safe command surfaces.

   Existing `apply`, `list-tools`, `matrix-tools`, `doctor`, and documentation
   are Darwin-first. Either:

   - add Linux-aware modes; or
   - add a smaller first command path for this target.

   The initial supported commands can be:

   ```bash
   nix build .#homeConfigurations.<linux-workbench-target>.activationPackage
   home-manager switch --flake .#<linux-workbench-target>
   ```

   Do not update examples that say Darwin-only until the commands really support
   Linux.

7. Add validation.

   Add checks that evaluate the Linux Home Manager target with placeholder
   public facts and with documented local-facts requirements. The checks should
   prove:

   - Darwin outputs still evaluate;
   - Linux Home Manager output evaluates;
   - Linux target does not import Homebrew/nix-darwin/macOS-only modules;
   - no global project-pinned toolchain toggle appears for Node.js, Go,
     Terraform, or OpenTofu;
   - modules consume `myconfig.hostContext` rather than reading raw facts.

8. Document rollout to the live LXC.

   Add a short runbook section that explains:

   - clone or worktree location on the LXC;
   - where local facts live;
   - build-only command;
   - switch command;
   - post-switch smoke checks.

   Example smoke checks:

   ```bash
   whoami
   hostname
   echo "$HOME"
   git --version
   zsh --version || true
   tmux -V || true
   nvim --version | head -1 || true
   direnv --version || true
   sops --version || true
   codex --version
   ```

   `codex --version` is a live host check only. It should verify the standalone
   installer path, not a Nix-managed Codex package.

## Non-Goals

- Do not convert the LXC to NixOS as part of this work.
- Do not move Proxmox, Tailscale, SSH, storage, or observability ownership out
  of `domus-ops`.
- Do not add global Node.js, Go, Terraform, or OpenTofu host-level toggles.
- Do not commit real user names, hostnames, private home directories, tokens, or
  machine-specific facts.
- Do not make `own_mac` or `work_mac` depend on the new Linux target.

## Acceptance Criteria

This issue is complete when:

1. `nix flake show` exposes the Linux Home Manager target.
2. Darwin targets still evaluate and build as before.
3. The Linux target builds an activation package on `x86_64-linux`.
4. The Linux target imports no Darwin/Homebrew/macOS-only modules.
5. The live workbench can run `home-manager switch --flake` successfully.
6. Shell, Git, tmux, Neovim, direnv, SOPS/age helpers, and common CLI tools are
   available after switch.
7. `codex --version` still returns the standalone upstream CLI version and is
   not provided by Nix.
8. Documentation clearly states that host/user identity comes from local facts
   and `myconfig.hostContext`, not committed literals.

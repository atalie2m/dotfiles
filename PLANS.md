# Dotfiles Redesign Plan: Reconciled Mutable Surfaces

This plan is written for an implementation agent. It assumes breaking changes are acceptable.

Hard constraints:
- **Denix stays.**
- **brew-nix stays.**
- **Shell/Terminal rewrite detection stays and remains intentional.** The design must keep a writable/user-owned layer while still providing drift detection, diff inspection, and an explicit adopt workflow.

## Design north star

### Problem framing
Some configuration artifacts must remain user-writable (shell entrypoints, Terminal.app preferences) while still being managed declaratively.

The sustainable architecture is to treat these artifacts as **reconciled mutable surfaces**:

- **desired**: repo source-of-truth (e.g., `apps/shell/managed/*`, `apps/terminal/*.terminal`)
- **actual**: live user/system state (e.g., `~/.bashrc`, `~/Library/Preferences/com.apple.Terminal.plist`)
- **lastApplied**: machine-local state (hashes) used for 3-way comparisons

A reconciler must support:
1. **drift detection** (`check`) using a 3-way comparison
2. **human-readable diff** (`--diff`) between desired and actual
3. **adopt** (`adopt`) that writes approved drift back into the repo source-of-truth

The repo already has a solid reconciler core (`nix/scripts/sync-core.sh`) and two adapters (`shell.sh`, `terminal.sh`). The redesign goal is to make reconciliation a first-class part of the Denix system, eliminate duplicated/imperative implementations, and tighten long-term maintainability.

### Target properties
- **Single source of truth per surface** (no “apply logic” duplicated across Nix modules and scripts).
- **Single owner per tool/service** (avoid two modules fighting over the same knob).
- **Transactional apply** where needed (Terminal.app) so `lastApplied` never advances unless the OS state truly changed.
- **Explicit migration paths** (commands/docs), not permanent legacy fallbacks.

---

## Progress snapshot (2026-03-05)

- Completed:
  - Phase 1 shell reconciliation migration landed:
    - `nix/scripts/apply.sh` no longer runs shell sync directly.
    - `nix/denix/modules/tools/shell/sync.nix` runs shell sync in Home Manager activation.
    - `README.md` updated for new shell sync behavior and options.
  - Phase 2A/2B landed in `terminal.sh`:
    - `terminal sync --apply` is implemented.
    - apply writes to a work plist and commits transactionally.
    - `lastApplied` writes are queued and only flushed after a successful commit.
  - Phase 2C (partial) landed:
    - `--default-profile` / `--startup-profile` apply flags are implemented.
    - apply smoke test now covers synthetic apply and commit-failure rollback.
  - Phase 3 landed:
    - `nix/denix/modules/tools/terminal/terminal-app.nix` is now a thin activation wrapper around `terminal.sh`.
    - `nix/denix/rices/dev/default.nix` no longer duplicates Terminal profile mappings.
  - Phase 4 landed:
    - brew-nix no longer directly controls `services.mac-app-util` or imports upstream Home Manager module.
    - ownership is signaled via `myconfig.tools.system.macAppUtil.*` dependency overrides.
    - `mac-app-util.nix` now uses `mkDefault false` instead of `mkForce false` for upstream service default.
  - Phase 5 landed:
    - shell/terminal state defaults now use `$XDG_STATE_HOME/dotfiles/sync/...`.
    - `terminal.sh` no longer reads/removes legacy `dotfiles/terminal/profiles` fallback state.
    - explicit migration command added: `nix run .#dotfiles -- migrate-state`.
  - Phase 2C remainder settled:
    - backup/snapshot behavior was removed from active Terminal reconciliation flow.
  - Regression tests currently pass:
    - `bash nix/scripts/sync-core-fake-adapter-test.sh`
    - `bash nix/scripts/sync-shell-smoke-test.sh`
    - `bash nix/scripts/sync-terminal-smoke-test.sh`
- Open blocker:
  - none.
- Immediate next milestone:
  - Phase 6/7 cleanup (surface contract tightening + docs/doctor UX polish).

### Code reality check (2026-03-05)
- `nix/scripts/terminal.sh` now supports check/apply/adopt/forget with transactional apply:
  - `sync_core_parse_cli_args 1 "$@"`
  - `sync_adapter_write_desired_to_actual` merges `.terminal` payloads into a work plist
  - `sync_adapter_write_last_applied_hash` queues updates in apply mode
  - `sync_adapter_after_apply` commits and flushes state only after successful verify
- `nix/scripts/sync-terminal-smoke-test.sh` now validates:
  - `--check` drift detection
  - `--adopt --in-place` export flow
  - `--apply` success path in synthetic mode
  - commit-failure path where state and plist remain unchanged
- `nix/denix/modules/tools/terminal/terminal-app.nix` is now thin orchestration:
  - activation delegates to `terminal.sh sync --apply`
  - module options keep orchestration concerns (`managedDir`, `defaultProfile`, `startupProfile`, `forceImport`, `failOnDrift`)

### Current active target
- Phase 6/7 polish:
  - tighten surface contracts and remove remaining redundant defensive paths.
  - document reconciled surfaces and operator workflows end-to-end.

---

## Phase 0 — Baseline and guardrails

### Outcomes
- Current behavior is reproducible.
- There are tests/commands that detect regressions while refactoring.

### Checklist
- [x] Record “known-good” command outputs for reference:
  - [x] `nix run .#dotfiles -- shell sync --check --details`
  - [x] `nix run .#dotfiles -- terminal sync --check --details`
- [x] Run existing tests:
  - [x] `bash nix/scripts/sync-core-fake-adapter-test.sh`
  - [x] `bash nix/scripts/sync-shell-smoke-test.sh`
  - [x] `bash nix/scripts/sync-terminal-smoke-test.sh`
- [x] Run repo checks:
  - [x] `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
  - Result: passing after formatting/lint cleanup.

### Success criteria
- All three sync tests pass.
- `nix flake check` passes on macOS.

### Current status (2026-03-05)
- [x] All three sync tests pass.
- [x] `nix flake check` passes on macOS.

---

## Phase 1 — Move shell reconciliation into Denix activation

### Intent
Stop treating shell reconciliation as a pre-step in `apply.sh`. Make it a first-class activation concern so:
- switch/build behavior is consistent regardless of entrypoint
- the reconciler is always run after Home Manager regenerates `hm-*` shell artifacts

### Implementation notes
- Use the existing reconciler: `nix/scripts/shell.sh sync --apply`.
- Keep the existing managed-block model (rewrite detection) exactly as-is.

### Checklist
- [x] Add a Denix module to run shell reconcile during Home Manager activation.
  - Suggested new module:
    - `nix/denix/modules/tools/shell/sync.nix`
    - `name = "tools.shell.sync"`
  - Options (minimum):
    - `enable` (bool, default: `tools.shell.enable`)
    - `forceApply` (bool, default: `false`) — maps to `shell sync --apply --force`
    - `failOnDrift` (bool, default: `true`) — when `false`, run `--check` and log but do not fail activation
  - Activation behavior:
    - order late (e.g. `lib.mkOrder 900`) so HM-generated files exist first
    - command:
      - `shell.sh sync --apply` (or `--apply --force` if configured)
      - if `failOnDrift = false`, prefer: `shell.sh sync --check --details` and ignore exit code
- [x] Remove shell reconciliation from `nix/scripts/apply.sh`.
  - Delete the block that executes `nix/scripts/shell.sh sync --apply`.
- [x] Update user-facing guidance (docs) to reflect that `apply` no longer runs shell sync explicitly.

### Success criteria
- Running `nix run .#apply -- --action switch` updates shell entrypoints solely via activation.
- Shell drift still blocks activation by default (unless `failOnDrift = false`).
- `bash nix/scripts/sync-shell-smoke-test.sh` still passes.

### Current status (2026-03-05)
- [x] Completed.

---

## Phase 2 — Unify Terminal.app apply into `terminal.sh` (and make it transactional)

### Intent
Right now, Terminal.app has two implementations:
- drift/adopt inspection in `nix/scripts/terminal.sh`
- a separate imperative apply implementation embedded in `nix/denix/modules/tools/terminal/terminal-app.nix`

This violates “single source of truth”. The goal is:
- **all Terminal profile logic lives in `terminal.sh` + `sync-core.sh`**
- Denix module becomes a thin orchestration layer
- apply is **transactional**: do not write `lastApplied` unless preferences import succeeds

### Key design constraint
`sync-core` writes `lastApplied` during per-item apply. Terminal apply should not advance state until after `defaults import` succeeds.

### Implementation strategy
Use adapter hooks/overrides to buffer state updates until commit:

- `terminal.sh` continues to work on a **work plist** (`work_plist`) like today.
- During apply, profile merges update `work_plist` (not the live prefs directly).
- Override state write in adapter:
  - implement `sync_adapter_write_last_applied_hash` in `terminal.sh`
  - in apply mode, write intended updates to a temp queue (not the real state dir)
- Add `sync_adapter_after_apply` to commit:
  - commit `work_plist` to live prefs (`defaults import`) (or to a synthetic plist when testing)
  - only after a successful commit:
    - compute hashes from a verified export
    - flush queued state updates to the real state directory

This keeps `sync-core` generic while giving Terminal the transactional semantics it needs.

### Checklist
- [x] **Phase 2A — Apply plumbing in `terminal.sh`**
  - [x] Extend `nix/scripts/terminal.sh` to support `--apply`.
    - Change `sync_core_parse_cli_args 0 "$@"` → `sync_core_parse_cli_args 1 "$@"`.
    - Update usage text and `sync_core_validate_force_usage` to allow `--force` with apply.
  - [x] Implement `sync_adapter_write_desired_to_actual`:
    - ensure `:"Window Settings"` exists in `work_plist`
    - delete existing `:"Window Settings":"<profile>"` if present
    - add dict container
    - `PlistBuddy Merge` the `.terminal` file into the container
    - (optional but recommended) verify merged hash matches desired hash
- [x] **Phase 2B — Transactional state commit**
  - [x] Add a temp queue file (e.g., `stateUpdateList`) in `terminal.sh`.
  - [x] Implement `sync_adapter_write_last_applied_hash`:
    - if `sync_core_mode == apply`, append the profile name to the queue and return success
    - otherwise, fall back to the default core behavior (write immediately)
  - [x] Implement `sync_adapter_after_apply`:
    - if mode != apply: no-op
    - else:
      - commit changes:
        - **normal mode**: `defaults import com.apple.Terminal "$work_plist"`
        - **test mode** (when `DOTFILES_TERMINAL_SYNC_PLIST` is set): write back into that plist file instead of importing
      - verify export (mirror the existing module’s verify flow, but keep it minimal)
      - flush queued state updates:
        - for each queued profile, compute hash from the verified export
        - write state file in the normal state dir
      - `killall cfprefsd` (best-effort)
- [ ] **Phase 2C — Profile defaults and behavior cleanup**
  - [x] Add `--default-profile` / `--startup-profile` flags to `terminal.sh` apply flow.
    - Preserve current semantics from `terminal-app.nix`.
  - [ ] Reduce defensive behavior (as defaults):
    - [ ] Backups/snapshots:
      - default **off** in the script
      - add optional flags to enable (and a Denix option to control)
  - [x] Update smoke test to cover apply in synthetic mode.
    - `nix/scripts/sync-terminal-smoke-test.sh` should:
      - mutate the synthetic plist
      - run `terminal sync --apply` and assert it updates the plist
      - ensure state updates only occur when commit succeeds

### Current status (2026-03-05)
- [x] `terminal sync --apply` exists and is transactional.
- [x] `bash nix/scripts/sync-terminal-smoke-test.sh` covers apply success and commit-failure rollback in synthetic mode.
- [ ] Backup/snapshot optional flags (if retained) are not implemented yet.

### Success criteria
- `nix run .#dotfiles -- terminal sync --apply` exists and works.
- `bash nix/scripts/sync-terminal-smoke-test.sh` passes without modifying real Terminal prefs.
- State (`lastApplied`) is not written if the apply commit fails.

---

## Phase 3 — Replace `terminal-app.nix` imperative apply with a thin orchestration layer

### Intent
Delete the large embedded activation script and call the canonical reconciler (`terminal.sh`).

### Checklist
- [x] Refactor `nix/denix/modules/tools/terminal/terminal-app.nix`:
  - [x] Remove the embedded apply implementation (the large activation script body).
  - [x] Replace with a small activation step that calls `terminal.sh sync --apply`.
    - Use `${inputs.self}/nix/scripts/terminal.sh` (store path is fine for apply).
    - Pass:
      - `--dir ${inputs.self}/apps/terminal` (or keep configurable)
      - `--default-profile` / `--startup-profile` from module options
      - `--force` when `cfg.forceImport` is true
      - If `cfg.failOnDrift` is false, prefer `--check` and ignore failures (mirror shell behavior)
- [x] Simplify options to reduce redundancy:
  - [x] Introduce `managedDir` (default: `${inputs.self}/apps/terminal`).
  - [x] Deprecate `profiles` / `extraProfiles` by removing them from active module options.
  - [x] Remove compile-time assertions that require enumerating profile names; validate at runtime instead.
- [x] Update rices to stop repeating profile mappings.
  - `nix/denix/rices/dev/default.nix`:
    - remove the large `profiles = { ... }` attrset
    - keep `defaultProfile` / `startupProfile`

### Current status (2026-03-05)
- [x] `terminal-app.nix` is now a thin orchestration layer.
- [x] Terminal profile apply logic is centralized in `terminal.sh`.
- [x] `nix run .#apply -- --host a2m_mac --action build --no-sudo` succeeds after refactor.

### Success criteria
- `terminal-app.nix` is small and only orchestrates.
- No Terminal profile apply logic exists outside `terminal.sh`.
- `darwin-rebuild switch` still applies Terminal profiles.

---

## Phase 4 — Single-owner policy: resolve `mac-app-util` ownership vs brew-nix

### Intent
Today, `tools.system.macAppUtil` and `tools.system.brewNix` both attempt to control `mac-app-util` (service enablement and/or activation behavior), causing conflicts (`mkForce` vs `mkIf`).

Establish **one owner** for mac-app-util behavior.

### Recommended ownership model
- **Owner:** `tools.system.macAppUtil`
- **Dependents:** brew-nix (and others) may *require* macAppUtil, but must not enable/disable the upstream service directly.

### Checklist
- [x] Remove direct mac-app-util control from `nix/denix/modules/tools/system/brew-nix.nix`:
  - removed `services.mac-app-util.enable = ...`
  - removed `home-manager.sharedModules = ... inputs.mac-app-util.homeManagerModules.default`
- [x] In `brew-nix.nix`, replace it with a dependency signal:
  - when `cfg.autoTrampolines.enable && !cfg.appLinks.enable`, set:
    - `myconfig.tools.system.macAppUtil.enable = lib.mkOverride 900 true`
    - `myconfig.tools.system.macAppUtil.systemService.enable = lib.mkOverride 900 true`
  - when `cfg.appLinks.enable`, keep trampoline cleanup in brew-nix activation.
- [x] In `mac-app-util.nix`, remove `mkForce` conflicts where possible.
  - switched upstream service default from `mkForce false` to `mkDefault false`.
  - kept ownership in this module’s activation scripts.

### Current status (2026-03-05)
- [x] brew-nix now signals dependency only; it no longer owns `services.mac-app-util`.
- [x] mac-app-util upstream service conflicts are reduced (`mkDefault` instead of `mkForce`).
- [x] `nix run .#apply -- --host a2m_mac --action build --no-sudo` succeeds with the ownership refactor.

### Success criteria
- Enabling brew-nix does not fight mac-app-util settings.
- There is exactly one codepath that generates trampolines.

---

## Phase 5 — Normalize state layout and provide explicit migrations

### Intent
Long-term sustainability requires state layout that is consistent and documented. Legacy fallbacks should not live forever.

### Proposed state layout
- `$XDG_STATE_HOME/dotfiles/sync/shell/*`
- `$XDG_STATE_HOME/dotfiles/sync/terminal-app/*`

### Checklist
- [x] Update default `state_dir` values:
  - `nix/scripts/shell.sh`: default to `$XDG_STATE_HOME/dotfiles/sync/shell/blocks`
  - `nix/scripts/terminal.sh`: default to `$XDG_STATE_HOME/dotfiles/sync/terminal-app/profiles`
- [x] Add an explicit migration command (do **not** auto-migrate silently):
  - New script: `nix/scripts/migrate-state.sh` (or a `dotfiles` subcommand)
  - Moves old state dirs to new locations (or rewrites in place).
  - Prints exactly what it changed.
- [x] Remove legacy fallback reads after migration is available:
  - `terminal.sh` currently reads from `dotfiles/terminal/profiles` as a fallback → remove.

### Success criteria
- A clean machine only uses the new state directories.
- Existing machines can migrate state with a single explicit command.
- Legacy fallback code is deleted.

---

## Phase 6 — Tighten surface contracts, delete overly defensive behavior

### Intent
Eliminate patterns that add complexity without paying for themselves, while keeping the intentional user-writable layer.

### Checklist
- [x] Terminal apply:
  - [x] remove backup/snapshot by default
  - [x] keep optional “make backup” behavior behind explicit options
- [x] Shell reconcile:
  - [x] keep managed-block boundaries
  - [x] ensure error messages clearly tell the user what changed and how to resolve:
    - `dotfiles -- shell sync --check --diff`
    - `dotfiles -- shell sync --adopt [--in-place]`
- [x] Remove repo-wide legacy behaviors that were only for safety:
  - [x] redundant state dir fallbacks
  - [x] duplicated logic (Nix module copies of script behavior)

### Success criteria
- The steady-state implementation for each surface is small and direct.
- Drift behavior is explicit: detect → inspect diff → adopt/force.

---

## Phase 7 — Documentation and operator UX

### Checklist
- [x] Add a short doc describing reconciled surfaces and workflows:
  - `docs/reconciled-surfaces.md`
  - include copy/paste commands:
    - drift check
    - diff view
    - adopt staging and in-place adopt
    - force apply semantics
- [x] Update `AGENTS.md` with:
  - where state lives
  - how to add a new reconciled surface adapter
- [x] Optional but recommended: extend `nix/scripts/doctor.sh` with drift checks
  - `shell sync --check` and `terminal sync --check`
  - gated by platform and whether the relevant tools are enabled

### Success criteria
- The “how do I handle drift?” workflow is documented end-to-end.
- A new adapter can be added by following docs + `sync-core` adapter requirements.

---

## Remaining execution plan (PR-sized slices)

This is the recommended merge order for remaining work.

### Slice A — Terminal `--apply` plumbing only (Phase 2A)
- Scope:
  - `nix/scripts/terminal.sh`
  - `nix/scripts/sync-terminal-smoke-test.sh` (minimal updates only if required)
- Changes:
  - Add `--apply` mode wiring and usage text.
  - Implement profile merge write-path in `sync_adapter_write_desired_to_actual`.
  - Do not yet change module orchestration (`terminal-app.nix` still owns activation apply).
- Validation:
  - `bash nix/scripts/sync-terminal-smoke-test.sh`
  - `nix run .#dotfiles -- terminal sync --check --details`
- Rollback note:
  - Revert `terminal.sh` apply wiring if any apply-mode regression appears outside synthetic test mode.

### Slice B — Transactional lastApplied commit (Phase 2B)
- Scope:
  - `nix/scripts/terminal.sh`
  - `nix/scripts/sync-terminal-smoke-test.sh`
- Changes:
  - Queue lastApplied writes during apply.
  - Commit work plist first; flush queued hashes only after successful commit/verify.
  - Ensure synthetic test mode can exercise commit success/failure.
- Validation:
  - `bash nix/scripts/sync-terminal-smoke-test.sh`
  - Add at least one failure-path assertion: commit failure must not write new state.
- Rollback note:
  - If commit verification is flaky, keep queue logic but gate verification behind a strict-but-deterministic check.

### Slice C — Default/startup profile flags + behavior cleanup (Phase 2C)
- Scope:
  - `nix/scripts/terminal.sh`
  - `nix/scripts/sync-terminal-smoke-test.sh`
  - `README.md`
- Changes:
  - Add `--default-profile` and `--startup-profile` options to `terminal.sh`.
  - Disable backup/snapshot behavior by default; keep explicit opt-in switches if retained.
- Validation:
  - `bash nix/scripts/sync-terminal-smoke-test.sh`
  - Manual local run:
    - `nix run .#dotfiles -- terminal sync --apply`
    - `nix run .#dotfiles -- terminal sync --check --details`
- Rollback note:
  - If default/startup mutation is risky, keep flags but no-op unless explicitly set.

### Slice D — Thin `terminal-app.nix` orchestration (Phase 3)
- Scope:
  - `nix/denix/modules/tools/terminal/terminal-app.nix`
  - `nix/denix/rices/dev/default.nix`
- Changes:
  - Replace embedded imperative script with a small activation call to `terminal.sh sync --apply`.
  - Retain module options needed for orchestration; deprecate redundant profile mapping options.
  - Mirror shell behavior for `failOnDrift`.
- Validation:
  - `nix run .#apply -- --host a2m_mac --action build`
  - `nix run .#dotfiles -- terminal sync --check --details`
- Rollback note:
  - Keep previous activation script in git history; do not keep dual paths in active code.

### Slice E — mac-app-util single-owner policy (Phase 4)
- Scope:
  - `nix/denix/modules/tools/system/brew-nix.nix`
  - `nix/denix/modules/tools/system/mac-app-util.nix`
- Changes:
  - Remove direct upstream service ownership from brew-nix.
  - Convert brew-nix behavior to dependency signaling only.
  - Remove `mkForce` conflicts in mac-app-util where possible.
- Validation:
  - `nix run .#apply -- --host a2m_mac --action build`
  - Manual check: no option conflict when `tools.system.brewNix.enable = true`.
- Rollback note:
  - Reintroduce temporary `mkOverride` priority in one module only if conflict cannot be resolved cleanly in one PR.

### Slice F — State migration + docs/doctor polish (Phases 5-7)
- Scope:
  - `nix/scripts/shell.sh`
  - `nix/scripts/terminal.sh`
  - `nix/scripts/migrate-state.sh` (new)
  - `nix/scripts/doctor.sh` (optional)
  - `docs/reconciled-surfaces.md` (new)
  - `AGENTS.md`
  - `README.md`
- Changes:
  - Move state defaults to `$XDG_STATE_HOME/dotfiles/sync/...`.
  - Provide explicit migration command and remove legacy read fallbacks.
  - Document adapter contract and drift resolution workflow.
- Validation:
  - `bash nix/scripts/sync-shell-smoke-test.sh`
  - `bash nix/scripts/sync-terminal-smoke-test.sh`
  - `nix flake check --override-input local path:$HOME/.config/dotfiles --override-input secrets path:$HOME/.config/dotfiles`
- Rollback note:
  - Migration script should be idempotent; if problems occur, restore from moved state directory backup and keep fallback reads one release longer.

### Active worksheet — Slice A/B detailed execution

This section is intentionally tactical so implementation can proceed without re-deriving scope.

#### Slice A checklist (Terminal `--apply` plumbing)
- [x] `nix/scripts/terminal.sh`: CLI and flag wiring
  - [x] Add usage line for `terminal sync --apply`.
  - [x] Switch parser call to `sync_core_parse_cli_args 1 "$@"`.
  - [x] Permit `--force` for apply mode (`sync_core_validate_force_usage` apply toggle).
- [x] `nix/scripts/terminal.sh`: write-path implementation
  - [x] Add helper to ensure `:"Window Settings"` exists in target plist before merge.
  - [x] Implement `sync_adapter_write_desired_to_actual`:
    - delete existing profile dict (best-effort)
    - add profile dict container
    - merge desired `.terminal` payload with `PlistBuddy Merge`
    - verify merged hash equals desired hash (recommended gate)
- [x] `nix/scripts/sync-terminal-smoke-test.sh`: minimal apply assertion
  - [x] Add one synthetic plist case that verifies `terminal sync --apply` updates current profile data.
  - [x] Keep all operations under `DOTFILES_TERMINAL_SYNC_PLIST` (no real prefs writes).

#### Slice B checklist (transactional lastApplied commit)
- [x] `nix/scripts/terminal.sh`: queue-based state writes in apply mode
  - [x] Add temp queue file (e.g., `state_update_list`) with cleanup hook.
  - [x] Override `sync_adapter_write_last_applied_hash`:
    - in apply mode: queue profile IDs only
    - in non-apply modes: fall back to default immediate write
- [x] `nix/scripts/terminal.sh`: commit hook
  - [x] Implement `sync_adapter_after_apply`:
    - commit `work_plist` to live Terminal prefs via `defaults import`
    - synthetic mode (`DOTFILES_TERMINAL_SYNC_PLIST`): write back to that plist path instead
    - export/verify resulting prefs plist
    - compute/write `lastApplied` hashes from verified state for queued profiles
    - `killall cfprefsd` best-effort
  - [x] Ensure queue flush is skipped if commit/import fails.
- [x] `nix/scripts/sync-terminal-smoke-test.sh`: failure-path coverage
  - [x] Add one assertion that failed apply commit does not advance state files.
  - [x] Prefer deterministic synthetic failure (explicit test hook) over flaky OS-level failure simulation.

#### Explicitly out of scope for Slice A/B
- `nix/denix/modules/tools/terminal/terminal-app.nix` ownership/orchestration changes (Slice D)
- `defaultProfile` / `startupProfile` script flags (Slice C)
- backup/snapshot default policy changes (Slice C)

### Cross-slice acceptance gate
- [ ] Each slice passes its local smoke tests before merge.
- [ ] No slice introduces a second active apply implementation for the same surface.
- [ ] `nix flake check` is green before closing this plan.

---

## Notes for the implementer

### Files expected to change significantly
- `nix/scripts/apply.sh`
- `nix/denix/modules/tools/shell/sync.nix`
- `nix/scripts/terminal.sh`
- `nix/scripts/sync-terminal-smoke-test.sh`
- `README.md`
- `nix/denix/modules/tools/terminal/terminal-app.nix`
- `nix/denix/modules/tools/system/brew-nix.nix`
- `nix/denix/modules/tools/system/mac-app-util.nix`

### Existing reference implementations
- Terminal apply logic to port (and simplify):
  - `nix/denix/modules/tools/terminal/terminal-app.nix`
- Sync adapter contract:
  - `nix/scripts/sync-core.sh` (`sync_adapter_*` hooks and defaults)
  - `nix/scripts/sync-core-fake-adapter-test.sh`

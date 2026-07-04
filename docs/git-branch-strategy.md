# Git Branch Strategy

This repository uses trunk-based development with PR-centered change
governance.

## Core Rule

Pull requests are the system's change objects. Branch names are disposable ref
handles, not authority.

```text
Branch names are not authority.
The pull request is the change object.
The policy verdict is the control point.
The merge gate is the enforcement point.
Service namespaces are only confinement.
```

For this dotfiles repository, the ref classes are:

```text
main
maint/<series>
stabilize/<train>
svc/<principal-id>/**
dependabot/** | dependabot-* | dependabot_*
gh-readonly-queue/**
everything else = human work branch
```

Meanings:

- `main`: the normal protected integration line.
- `maint/<series>`: protected maintenance lines if this repository needs them.
- `stabilize/<train>`: short-lived hardening lines with an expiry.
- `svc/<principal-id>/**`: confinement namespace for an approved service
  principal. The suffix is writer-owned detail and has no policy meaning.
- `dependabot/**`, `dependabot-*`, and `dependabot_*`: vendor-controlled
  Dependabot refs.
- `gh-readonly-queue/**`: GitHub merge queue internals. Do not create, edit, or
  garbage-collect these refs.
- Everything else: human work branch. No human branch naming convention is
  enforced.

There is no `chg/**` namespace.

## Dotfiles Service Principal Boundary

This repository can affect the operator workstation, Home Manager state, and
local tool behavior. Install service principals only when they have an explicit
owner, inventory entry, and scoped write path.

Do not install a general unattended task-agent credential for dotfiles. If a
machine-generated change is needed, prefer a reviewed handoff or an approved
service principal under `svc/<principal-id>/**`.

## Branch Names Are Not Policy Inputs

Policy lanes are derived from observed facts such as base branch, latest pusher
principal, sponsor, reviews, diff paths and hunks, CODEOWNERS impact,
principal inventory, and check results.

Do not derive policy from:

- branch suffix
- human branch name
- `feat`, `fix`, `chore`, or similar prefixes
- producer self-reporting
- PR label alone
- PR body alone

Do not encode or parse these values in branch names:

- provenance
- ownership
- run IDs
- dates
- environment names
- producer type
- policy lane
- issue type
- release target

Put those details in PR bodies, policy verdicts, evidence files, workflow
metadata, release ledgers, or runtime state instead.

## Claim Flow

Claim service-principal work by opening a new human PR. Do not keep pushing to
the service namespace.

```sh
git fetch origin
git switch -c alice/dotfiles-manual-fix origin/svc/task-runner/some-opaque-branch
git push origin alice/dotfiles-manual-fix
```

The new PR records:

```text
Claimed-from: #123
Original-principal: task-runner[bot]
Claimed-by: @alice
Reason: human owner taking accountability for the diff
```

Close the original service-principal PR as claimed/superseded.

## Merge And Apply

Merge does not mean apply. The Git state describes desired userland
configuration. `home-manager switch`, `darwin-rebuild switch`, or
`nix run .#apply` remains a deliberate operator action unless the active task
explicitly authorizes it.

## Reserved Names

Human work branches are allowed by default, except for reserved namespaces and
the migration blocklist:

```text
master
develop
production
staging
env/**
release/**
bot/**
svc/**
maint/**
stabilize/**
gh-readonly-queue/**
dependabot/**
dependabot-*
dependabot_*
```

Use `maint/**` for long-lived maintenance and `stabilize/**` for short-lived
hardening. Do not use environment branches.

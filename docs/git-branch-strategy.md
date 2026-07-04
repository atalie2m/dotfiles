# Git Branch Strategy

This repository uses trunk-based development with credential-class branch
namespaces.

## Core Rule

Branch names expose only the credential class in the first path segment.
Everything after that segment is writer-owned detail.

For this dotfiles repository, allowed branches are:

```text
main
supervised/**
deps/**
```

Meanings:

- `main`: protected trunk.
- `supervised/**`: pushed with a human or supervised-agent credential.
- `deps/**`: pushed with a dependency automation credential.

Policy reads only `supervised` or `deps`. A writer may choose any suffix shape
that avoids collisions.

## No Unattended Agent Namespace

Do not install unattended task-agent credentials for this repository.
`unattended/**` is not a normal dotfiles namespace because this repo can affect
the operator workstation, Home Manager state, and local tool behavior.

If an unattended change must be proposed, it should happen through an external
reviewed handoff. A human or supervised agent then takes accountability by
creating a `supervised/**` branch.

## Branch Suffixes Are Not Policy

Do not parse or enforce the branch suffix. Do not use branch names as:

- provenance
- ownership
- run IDs
- dates
- environment names
- issue types
- release targets

Put those details in PR bodies, evidence files, workflow metadata, or release
ledgers instead.

## Claim Flow

Humans do not push to `unattended/**`. If an unattended branch exists elsewhere
and a human takes responsibility for the diff, create a new supervised branch:

```sh
git fetch origin
git switch -c supervised/claim-dotfiles-fix origin/unattended/some-opaque-branch
git push origin supervised/claim-dotfiles-fix
```

The new PR records:

```text
Claimed-from: #123
Source-branch: unattended/some-opaque-branch
Source-head: abcdef1234567890
Claimed-by: @alice
Claim-reason: human owner taking accountability for the diff
```

Close the original unattended PR as claimed/superseded/do-not-merge.

## Merge And Apply

Merge does not mean apply. The Git state describes desired userland
configuration. `home-manager switch`, `darwin-rebuild switch`, or
`nix run .#apply` remains a deliberate operator action unless the active task
explicitly authorizes it.

## Denylist Is Advisory

The policy is an allowlist:

```text
main
supervised/**
deps/**
```

Names such as `develop`, `master`, `staging`, `production`, `prod`,
`release/*`, `env/*`, `app-handoff/*`, `agent/*`, `feat/*`, `fix/*`,
`chore/*`, and `unattended/*` are migration or error-message examples, not the
policy mechanism.

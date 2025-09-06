# Web Dev Template (Nix flake)

Quick start:

```bash
# initialize a repo from this template
nix flake init -t github:atalie2m/dotfiles#web-dev

# enter dev shell
nix develop
```

What you get:

- DevShell: Node.js 22, pnpm, bun, wrangler, awscli2, jq, yq, mkcert, just
- Formatters: Prettier via treefmt (run: `nix run .#format`)
- Checks: `nix flake check` runs treefmt and pre-commit hooks
- App: `nix run .#dev`

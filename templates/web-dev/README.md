# Web Dev Template (Nix flake)

Quick start:

```bash
# initialize a repo from this template
nix flake init -t github:atalie2m/dotfiles#web-dev

# enter dev shell
nix develop
```

What you get:

- DevShell: Node.js 22, pnpm, bun, deno, TypeScript, Playwright, redocly, wrangler, netlify/supabase/turso CLIs, awscli2, jq, yq, mkcert, just
- Project npm tools: `package.json` pins Vite, Vitest, Storybook, Nx, Knip, OpenAPI/GraphQL CLIs, Drizzle Kit, Vercel, and Surge for project-local installs
- Optional layers: uncomment entries in `enabledProfiles` for `api-db`, `docs`, `release`, `container-oci`, `kubernetes`, `infra-iac`, `ai-coding`, `model-hf`, or `native-debug`
- Formatters: Prettier via treefmt (run: `nix run .#format`)
- Checks: `nix flake check` runs the template's treefmt-based checks
- App: `nix run .#dev`

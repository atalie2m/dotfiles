Local secrets (sops + age)

This repository no longer stores secrets inside the repo. Instead, provide a local secrets input at:

- `~/.config/dotfiles/` (contains `secrets.nix` and `files/`)

The in-repo `nix/secrets/` directory is a stub for public evaluation only. Do not place secrets in this repo.

Minimum layout

```
~/.config/dotfiles/
├── facts.nix
├── secrets.nix
├── .sops.yaml
└── files/
    └── ai.env.sops.yaml
```

Quick start

- Generate an age key if you do not already have one:
  - `mkdir -p ~/.config/sops/age`
  - `age-keygen -o ~/.config/sops/age/keys.txt`
- Get your public key: `age-keygen -y ~/.config/sops/age/keys.txt`.
- Create `~/.config/dotfiles/.sops.yaml` (do not commit private keys):

  ```yaml
  creation_rules:
    - path_regex: files/.*\.(yaml|json|env)$
      age: ["AGE_PUBLIC_KEY_HERE"]
  ```

- Encrypt a file (example):

  ```bash
  sops --encrypt --in-place ~/.config/dotfiles/files/ai.env.sops.yaml
  ```

Example `secrets.nix`

```nix
{
  files = {
    aiEnv = {
      sopsFile = ./files/ai.env.sops.yaml;
      targetPath = ".config/dotfiles/ai.env";
      mode = "0600";
    };
  };
}
```

Notes

- `sops-nix` materializes secrets as files at activation time with strict permissions.
- Encrypted files may live on disk; plaintext should not be committed or written to the Nix store.
- Source materialized files in your shell config only if they exist.

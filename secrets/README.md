SOPS + age setup (CLI-only)

This repository currently installs the `sops` and `age` CLI tools only. It does not enable the sops-nix modules or auto-generate keys during nix-darwin/Home Manager switches.

Quick start

- Generate an age key if you do not already have one:
  - `mkdir -p ~/.config/sops/age`
  - `age-keygen -o ~/.config/sops/age/keys.txt`
- Get your public key: `age-keygen -y ~/.config/sops/age/keys.txt`.
- Create a `.sops.yaml` in this `secrets/` directory (do not commit private keys):

  ```yaml
  creation_rules:
    - path_regex: secrets/.*\.(yaml|json|env)$
      age: ["AGE_PUBLIC_KEY_HERE"]
  ```

- Encrypt a file (example):

  ```bash
  sops --encrypt --in-place secrets/example.yaml
  ```

Notes

- Do not commit unencrypted secrets.
- Rotate or add recipients by updating `.sops.yaml` and re-encrypting.
- If you later wire in sops-nix, see its docs for managing `sops.secrets` in Nix.

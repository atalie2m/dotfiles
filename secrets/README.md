SOPS + age setup

This repository integrates sops-nix for both nix-darwin and Home Manager. Keys and secrets are not committed.

Quick start

- After switching the configuration, an age key is generated at `~/.config/sops/age/keys.txt` if missing.
- Get your public key: `age-keygen -y ~/.config/sops/age/keys.txt`.
- Create a `.sops.yaml` in this `secrets/` directory (don’t commit private key):

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
- See Mic92/sops-nix docs for managing `sops.secrets` in Nix if you later want Nix to materialize files.


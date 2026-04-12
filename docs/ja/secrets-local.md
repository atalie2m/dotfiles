[English version](../secrets-local.md)

# ローカル secrets（sops + age）

このリポジトリは secret を repo 内に保存しません。代わりに、次の場所で local secrets input を提供してください。

- `~/.config/dotfiles/`（`secrets.nix` と `files/` を含む）

repo の default secrets input は意図的に inert です。`secrets.nix` が存在しない場合、secret の materialization は no-op になります。secret をこの repo に置かないでください。

## 最小レイアウト

```
~/.config/dotfiles/
├── facts.nix
├── secrets.nix
├── .sops.yaml
└── files/
    └── ai.env.sops.yaml
```

## クイックスタート

- まだ age key を持っていない場合は生成します。
  - `mkdir -p ~/.config/sops/age`
  - `age-keygen -o ~/.config/sops/age/keys.txt`
- 公開鍵を取得します。`age-keygen -y ~/.config/sops/age/keys.txt`
- `~/.config/dotfiles/.sops.yaml` を作成します（秘密鍵は commit しないでください）。

  ```yaml
  creation_rules:
    - path_regex: files/.*\.(yaml|json|env)$
      age: ["AGE_PUBLIC_KEY_HERE"]
  ```

- ファイルを暗号化します（例）。

  ```bash
  sops --encrypt --in-place ~/.config/dotfiles/files/ai.env.sops.yaml
  ```

## `secrets.nix` の例

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

## メモ

- `sops-nix` は activation 時に strict permission 付きの file として secret を materialize します。
- 暗号化ファイルは disk 上に置けますが、平文は commit せず、Nix store にも書き込まないでください。
- materialize された file は、存在する場合にだけ shell config から source してください。

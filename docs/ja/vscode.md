[English version](../vscode.md)

# VS Code profile

このリポジトリは、1 つの VS Code app を対象にし、native VS Code profile を writable な runtime state に reconcile します。
isolated per-instance runtime directory はもう使いません。

`tools.editor.vscode.enable = true` のとき、dotfiles は `dotfiles-sync-vscode` engine を Home Manager に install します。
Visual Studio Code.app 自体は install しません。手動で install するか、`VSCODE_CODE_BIN` を指定してください。
activation-time sync が有効でも VS Code がまだ install されていなければ、dotfiles は fail せず skip を記録します。
module を無効にしたまま手動で sync したい場合は、通常どおり VS Code を install するか、`VSCODE_CODE_BIN` を自分で指定してください。
`sync vscode` には `HOME` も必要です。その他の supported runtime override は [`docs/commands.md`](commands.md#runtime-overrides) にまとまっています。

## managed layout

profile は `apps/vscode/<name>/` に置きます。

- `apps/vscode/_default/`
  - すべての managed profile に適用される shared layer
  - それ自体は runtime profile ではない
- `apps/vscode/native/`
  - display name `Native` の custom native profile として管理される
- `apps/vscode/<name>/`
  - それ以外の directory は native custom profile に対応する
  - display name は directory 名から導出される（`data-science` -> `Data Science`, `web` -> `Web`）

注意: VS Code の built-in `Default` profile は意図的に unmanaged です。`sync vscode` はそこを変更しないため、既存の extension や settings は保持されます。

## stock Darwin profile と VS Code

stock profile のうち VS Code sync surface を install するのは **`pro`** と **`ultra`** です。Visual Studio Code.app 自体は手動 install 前提です。`pro` は setup sync を実行しません。`ultra` は activation 中に VS Code profile を reconcile します。VS Code がすでにある machine で手動適用したい場合は `nix run .#dotfiles -- sync vscode --apply` を明示的に実行してください。自分の設定で activation-time sync を使いたい場合は `tools.editor.vscode.sync.enable = true` を設定します。

### extension 一括 install: source of truth

ultra は、大きめの repo-owned extension set を持つことを想定しています。**何を install / remove するかは `apps/vscode/` にある一覧がすべて**であり、別の ad hoc な list は使いません。

- `apps/vscode/_default/extensions.txt` — すべての managed profile に merge される shared extension ID
- `apps/vscode/<profile>/extensions.txt` — その profile 専用の追加 ID（例: `native/`, `web/`, `data-science/`, `writing/`）

profile ごとの effective repo-owned extension は `_default` とその profile file の union で、extension ID 単位で unique になります（下の Effective extensions を参照）。ここに行を追加・削除すると、次の apply に反映されます。

完全に独立した profile 管理にしたいなら、`apps/vscode/_default/` の file を空にし、settings / extensions / default-disabled entry を profile ごとにだけ定義してください。

サポートする file:

- `settings.json`
- `extensions.txt`
- `default-disabled-extensions.txt`

`default-disabled-extensions.txt` は bootstrap-only input です。
これは launch time ではなく `sync vscode --apply` を通じて適用されます。

## runtime model

`sync vscode` は repo から desired profile state を構築し、それを VS Code の native profile storage に書き込みます。
CLI entrypoint は Rust engine（`dotfiles-sync-vscode`）にのみ dispatch します。

- Effective settings:
  - `_default/settings.json` と `<profile>/settings.json` の再帰 merge
- Effective extensions:
  - `_default/extensions.txt` と `<profile>/extensions.txt` を合成し、extension ID 単位で unique にする
- Runtime ownership:
  - effective managed profile settings file は repo が所有する
  - effective extension ID は repo が所有する
- Mutable drift:
  - managed settings file は apply で収束する
  - user-added extension は保持される
  - repo-owned settings / extension を repo から削除すると次の apply で削除される

この mutable model を支えるため、sync は VS Code sync state directory に profile ごとの最小限の local state を保持します。
その state が記録するもの:

- 以前 repo が所有していた extension ID
- 現在の profile で bootstrap 済みの default-disabled extension ID

state schema に関する補足:

- 現在の schema version は `4`
- 古い state file や malformed な state file は `needs-apply` として扱う
- apply 時に current schema で state を書き直す

## runtime location

macOS では:

- custom profile の settings は `~/Library/Application Support/Code/User/profiles/<profile-id>/settings.json`
- `native` も独自の profile id を持つ custom profile として同じ場所に管理される
  - `~/Library/Application Support/Code/User/profiles/<native-profile-id>/settings.json`
- sync state の default は `${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/vscode`

`sync vscode` は必要に応じて custom profile を bootstrap し、managed state の書き込み前に VS Code の profile registry を更新します。

## コマンド

public sync entrypoint を使ってください。

```bash
# すべての managed profile を check
nix run .#dotfiles -- sync vscode --check

# detail や projected diff を表示して check
nix run .#dotfiles -- sync vscode --check --details
nix run .#dotfiles -- sync vscode --check --details --diff

# すべての managed profile を apply
nix run .#dotfiles -- sync vscode --apply

# 1 つの repo profile directory に限定
nix run .#dotfiles -- sync vscode --check --profile web
nix run .#dotfiles -- sync vscode --apply --profile native

# source や state location を override
nix run .#dotfiles -- sync vscode --apply --managed-dir /path/to/apps/vscode
nix run .#dotfiles -- sync vscode --apply --state-dir /path/to/state
```

flag:

- `--check`
- `--apply`
- `--details`
- `--diff`
- `--profile <name>`
- `--managed-dir <path>`
- `--state-dir <path>`

`sync vscode --apply` は、`tools.editor.vscode.enable = true` かつ `tools.editor.vscode.sync.enable = true` のときに Home Manager activation 中に実行することもできます。
stock capability bundle は `tools.editor.vscode.sync.enable = false` のままにしているため、自動 reconcilaition が必要な場合だけ自分の設定で明示的に有効にしてください。
`code` または Visual Studio Code.app が見つからない場合、activation は skip message を出して続行します。

## 手動切り替え

profile の選択は手動のままです。
VS Code UI で切り替えるか、upstream の profile support を使って起動してください。

```bash
code --profile "Web"
code --profile "Data Science"
```

`sync vscode` は profile の中身を管理しますが、active profile 自体は選びません。

## bootstrap-only な default-disabled extension

dotfiles で install しつつ、profile を初回 bootstrap したときだけ default で無効化したい extension がある場合は、次を追加します。

- `apps/vscode/_default/default-disabled-extensions.txt`
- `apps/vscode/<profile>/default-disabled-extensions.txt`

これらの file は `sync vscode --apply` の間に merge され、重複除去されます。
seed は bootstrap-only です。

- 新しく追加された extension ID は、その profile の disabled extension state に一度だけ追加される
- その後 user が VS Code で明示的に有効化した場合、将来の apply で再び無効化しない
- 後から `default-disabled-extensions.txt` に新しい extension ID を足した場合、次の apply はその新しい ID だけを seed する

これは launch behavior ではなく sync state の一部です。
VS Code は upstream の profile selector を使って通常どおり起動します。

```bash
code --profile "Web"
code --profile "Data Science"
```

## mutable behavior と precedence

mutable model を制御するのは `sync vscode --apply` のみです。

- `extensions.txt` にある repo-owned extension は install / uninstall される
- `settings.json` にある managed profile settings は fully repo-owned file として書き直される
- repo-owned でない user-added extension ID は保持される
- default-disabled extension ID は `default-disabled-extensions.txt` から一度だけ bootstrap される

つまり:

- VS Code UI で extension を追加しても、後で dotfiles が ownership を持たない限り sync はそれを削除しない
- managed profile 内で manual に settings を変えても、次の apply で上書きされる
- managed profile の `settings.json` に malformed な JSON があっても、次の apply で drift として上書き修復される
- VS Code UI で extension を disable / enable しても repo state は変わらない
- `default-disabled-extensions.txt` から bootstrap 済みだった extension を後で user が有効化した場合、その状態は将来の apply でも保持される
- この model には launch helper や launch-time disable flag はない

## user-added extension が削除されるとき

user-added extension は、repo-owned になったあとで repo から削除されない限り install されたままです。

例:

- VS Code で `foo.bar` を手動 install する
  - `sync vscode --apply` はそれを保持する。dotfiles は ownership を持っていないため
- 後で `foo.bar` を `apps/vscode/_default/extensions.txt` に追加する
  - ここで dotfiles が ownership を持つ
- その後 repo から `foo.bar` を削除して `sync vscode --apply` を実行する
  - 以前 repo-owned だったが今は desired でないため、dotfiles が uninstall する

同じ ownership rule は profile ごとに適用されます。
`apps/vscode/web/extensions.txt` にだけ追加された extension は、`Web` profile に対してだけ owned です。

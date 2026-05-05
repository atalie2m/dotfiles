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

## Codex Slack 通知

`scripts/codex-slack-notification` は Slack credential を次の file から読みます。

```text
~/.config/dotfiles/files/codex/slack-bot-token
~/.config/dotfiles/files/codex/slack-channel-id
~/.config/dotfiles/files/codex/slack-webhook-url
```

これらの file は local のまま、mode `0600` で管理してください。`slack-bot-token` には
`chat:write` 付きの `xoxb-...` Bot User OAuth token、`slack-channel-id` には投稿先の
Slack channel ID を置きます。`slack-webhook-url` は任意の fallback です。Codex lifecycle
hook からこの script を呼び、Slack credential 値は Codex config と Git に入れないでください。

Slack 固有の整形、投稿、thread-state、fallback、error-log logic は
`scripts/lib/agent_notifications/slack.py` にあります。実行 script は Codex adapter なので、
将来の coding-agent adapter は credential handling を複製せず、同じ local secret file と
Slack transport を再利用できます。

thread 対応には、その Slack app / bot user が投稿先 channel に投稿できる必要があります。
private channel では bot を invite してください。public channel では bot を invite するか、
app の bot scope に `chat:write.public` を追加して app を reinstall してください。

一時的な override として次も受け付けます。

- `CODEX_SLACK_BOT_TOKEN_FILE` / `CODEX_SLACK_BOT_TOKEN`
- `CODEX_SLACK_CHANNEL_ID_FILE` / `CODEX_SLACK_CHANNEL_ID`
- `CODEX_SLACK_WEBHOOK_FILE` / `CODEX_SLACK_WEBHOOK_URL`
- `CODEX_SLACK_THREAD_STATE_FILE`
- `CODEX_SLACK_QUESTION_STATE_FILE`
- `CODEX_SLACK_ERROR_LOG_FILE`
- `CODEX_SLACK_INCLUDE_CONTEXT=1`
- `CODEX_SLACK_REPLY_MENTION`（default は `<!channel>`、空文字で無効化）
- `CODEX_SLACK_REPLY_MENTION_EVENTS`（comma-separated event names）
- `CODEX_SLACK_REPLY_BROADCAST=1`
- `CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1`

使い方:

1. Slack credential を local に保存します。

   ```bash
   mkdir -p ~/.config/dotfiles/files/codex
   printf '%s\n' 'xoxb-...' \
     > ~/.config/dotfiles/files/codex/slack-bot-token
   printf '%s\n' 'C0123456789' \
     > ~/.config/dotfiles/files/codex/slack-channel-id
   chmod 0600 \
     ~/.config/dotfiles/files/codex/slack-bot-token \
     ~/.config/dotfiles/files/codex/slack-channel-id
   ```

   任意の webhook fallback:

   ```bash
   printf '%s\n' 'https://hooks.slack.com/services/...' \
     > ~/.config/dotfiles/files/codex/slack-webhook-url
   chmod 0600 ~/.config/dotfiles/files/codex/slack-webhook-url
   ```

2. Codex lifecycle hook を `~/.codex/config.toml` に追加します。

   ```toml
   [features]
   codex_hooks = true

   # turn 完了の fallback です。SessionStart で transcript path が取れる場合、
   # 通常の完了通知は transcript watcher 側が送ります。
   [[hooks.Stop]]
   [[hooks.Stop.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification"
   timeout = 10
   statusMessage = "Sending Codex Slack notification"

   # Codex thread title、Plan Mode 質問、その transcript に紐づく完了 reply を
   # transcript watcher で拾います。
   [[hooks.SessionStart]]
   [[hooks.SessionStart.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification --spawn-question-watcher"
   timeout = 5
   statusMessage = "Starting Codex Slack transcript watcher"

   # 作業中の approval / permission request を拾います。
   [[hooks.PermissionRequest]]
   [[hooks.PermissionRequest.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification"
   timeout = 10
   statusMessage = "Sending Codex approval Slack notification"
   ```

3. Slack に投稿せず payload だけ確認します。

   ```bash
   CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
     /path/to/dotfiles/scripts/codex-slack-notification <<'JSON'
   {
     "hook_event_name": "Stop",
     "cwd": "/path/to/project",
     "last_assistant_message": "Dry-run notification."
   }
   JSON
   ```

thread state は local の次の path に保存されます。

```text
~/.local/state/dotfiles/codex-slack-threads.json
~/.local/state/dotfiles/codex-slack-question-watch.json
~/.local/state/dotfiles/codex-slack-notification.log
```

Slack が `channel_not_found` を返す場合は、その Slack app / bot user を投稿先 channel
に invite するか、Bot User OAuth token と同じ workspace installation の channel ID を
使ってください。Incoming webhook fallback では通知自体は継続できますが、local の
`thread_ts` map は更新できません。thread 対応には Bot User OAuth token による
`chat.postMessage` の成功が必要です。Bot / webhook の失敗は credential 値を書かずに
`codex-slack-notification.log` へ記録します。

`SessionStart` は transcript watcher を起動し、watcher が Codex の生成 `thread_name_updated`
title event から `Codex: <title> (<repo>)` 形式の Slack 親 message を作ります。title event が
無い場合は最初の user prompt から短い title を作り、それも無ければ `Codex: <repo>` に fallback
します。後から title event が来れば更新します。watcher は Plan Mode 質問と `task_complete` record
もその transcript から投稿するため、同じ repo で Codex session が並行していても「cwd の最新 session」
推定に依存しません。対応が必要な
通知や完了通知は default で `<!channel>` 付きの thread reply として投稿します。
`CODEX_SLACK_REPLY_BROADCAST=1` を設定しない限り、channel timeline には再掲しません。

bot token と channel id が設定されている場合、helper はまず threaded Bot API posting を試します。
Bot API posting に失敗した場合、対応が必要な通知や完了通知は incoming webhook に fallback
します。thread parent event は webhook message では Codex と Slack thread の対応を維持できない
ため skip します。unthreaded な best-effort 通知より hard failure を優先したい場合だけ
`CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1` を設定します。

4. 1 回だけ test notification を送ります。

   ```bash
   /path/to/dotfiles/scripts/codex-slack-notification --event-name setup-test <<'JSON'
   {
     "cwd": "/path/to/project",
     "last_assistant_message": "Codex Slack notification setup test completed."
   }
   JSON
   ```

[日本語版はこちら](ja/secrets-local.md)

# Local secrets (sops + age)

This repository no longer stores secrets inside the repo. Instead, provide a local secrets input at:

- `~/.config/dotfiles/` (contains `secrets.nix` and `files/`)

The repo's default secrets input is intentionally inert. If `secrets.nix` is absent, secrets materialization becomes a no-op. Do not place secrets in this repo.

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

## Codex Slack notifications

`scripts/codex-slack-notification` reads Slack credentials from:

```text
~/.config/dotfiles/files/codex/slack-bot-token
~/.config/dotfiles/files/codex/slack-channel-id
~/.config/dotfiles/files/codex/slack-webhook-url
```

Keep those files local with mode `0600`. `slack-bot-token` must contain a
`xoxb-...` Bot User OAuth token with `chat:write`; `slack-channel-id` must
contain the target Slack channel ID. `slack-webhook-url` is optional fallback.
Use Codex lifecycle hooks to call the script; keep Slack credential values out
of the Codex config and out of Git.

Slack-specific formatting, posting, thread-state, fallback, and error-log logic
lives in `scripts/lib/agent_notifications/slack.py`. The executable script is
the Codex adapter, so future coding-agent adapters can reuse the same local
secret files and Slack transport without copying credential handling.

Thread support also requires the Slack app or bot user to be able to post to
the target channel. Invite the bot to private channels. For public channels,
either invite the bot or add `chat:write.public` to the app's bot scopes and
reinstall the app.

The script also accepts these one-off overrides:

- `CODEX_SLACK_BOT_TOKEN_FILE` / `CODEX_SLACK_BOT_TOKEN`
- `CODEX_SLACK_CHANNEL_ID_FILE` / `CODEX_SLACK_CHANNEL_ID`
- `CODEX_SLACK_WEBHOOK_FILE` / `CODEX_SLACK_WEBHOOK_URL`
- `CODEX_SLACK_THREAD_STATE_FILE`
- `CODEX_SLACK_QUESTION_STATE_FILE`
- `CODEX_SLACK_ERROR_LOG_FILE`
- `CODEX_SLACK_INCLUDE_CONTEXT=1`
- `CODEX_SLACK_REPLY_MENTION` (defaults to `<!channel>`; set empty to disable)
- `CODEX_SLACK_REPLY_MENTION_EVENTS` (comma-separated event names)
- `CODEX_SLACK_REPLY_BROADCAST=1`
- `CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1`

Usage:

1. Store Slack credentials locally:

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

   Optional webhook fallback:

   ```bash
   printf '%s\n' 'https://hooks.slack.com/services/...' \
     > ~/.config/dotfiles/files/codex/slack-webhook-url
   chmod 0600 ~/.config/dotfiles/files/codex/slack-webhook-url
   ```

2. Add Codex lifecycle hooks to `~/.codex/config.toml`:

   ```toml
   [features]
   codex_hooks = true

   # Fallback turn completion. Normal completion is sent by the transcript watcher
   # when SessionStart provided a transcript path.
   [[hooks.Stop]]
   [[hooks.Stop.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification"
   timeout = 10
   statusMessage = "Sending Codex Slack notification"

   # Transcript watcher for Codex thread titles, Plan Mode questions, and
   # completion replies tied to this exact Codex transcript.
   [[hooks.SessionStart]]
   [[hooks.SessionStart.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification --spawn-question-watcher"
   timeout = 5
   statusMessage = "Starting Codex Slack transcript watcher"

   # Approval or permission requests while Codex is working.
   [[hooks.PermissionRequest]]
   [[hooks.PermissionRequest.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification"
   timeout = 10
   statusMessage = "Sending Codex approval Slack notification"
   ```

3. Preview the Slack payload without posting:

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

Thread state is stored locally at:

```text
~/.local/state/dotfiles/codex-slack-threads.json
~/.local/state/dotfiles/codex-slack-question-watch.json
~/.local/state/dotfiles/codex-slack-notification.log
```

If Slack returns `channel_not_found`, invite the Slack app or bot user to the
target channel, or use a channel ID from the same workspace installation as the
Bot User OAuth token. Incoming webhook fallback keeps notifications flowing, but
it cannot populate the local `thread_ts` map, so thread support requires
successful `chat.postMessage` calls through the Bot User OAuth token. Bot or
webhook failures are recorded in `codex-slack-notification.log` without writing
credential values.

`SessionStart` starts a transcript watcher, and the watcher creates the Slack
parent from Codex's generated `thread_name_updated` title event when available.
Parent messages use `Codex: <title> (<repo>)`. If a title event is unavailable,
the first notification derives a short title from the first user prompt before
falling back to `Codex: <repo>`, and a later title event updates it. The watcher
also posts Plan Mode questions and `task_complete` records from that exact
transcript, so parallel Codex sessions in the same repo do not depend on "latest
session for cwd" inference. Actionable or terminal
notifications are posted as thread replies with `<!channel>` by default. They
are not broadcast into the channel timeline unless `CODEX_SLACK_REPLY_BROADCAST=1`
is set.

When bot token and channel id are configured, the helper tries threaded Bot API
posting first. If Bot API posting fails, actionable and completion
notifications fall back to the incoming webhook; thread-parent events are
skipped because a webhook message cannot maintain the Codex-to-Slack thread map.
Set `CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1` only when you prefer hard
failure over unthreaded best-effort notifications.

4. Send a one-off test notification:

   ```bash
   /path/to/dotfiles/scripts/codex-slack-notification --event-name setup-test <<'JSON'
   {
     "cwd": "/path/to/project",
     "last_assistant_message": "Codex Slack notification setup test completed."
   }
   JSON
   ```

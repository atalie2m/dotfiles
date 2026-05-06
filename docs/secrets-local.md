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

`dotfiles agent-notify codex` reads Slack credentials from:

```text
~/.config/dotfiles/files/agent-notifications/slack-bot-token
~/.config/dotfiles/files/agent-notifications/slack-channel-id
~/.config/dotfiles/files/agent-notifications/slack-webhook-url
```

The stock Darwin profile toggle for this notification runtime is
`tools.aiCodingAgent.codex.slackNotifications.enable`. It is enabled in
`ultra`, not `pro`.

Keep those files local with mode `0600`. `slack-bot-token` must contain a
`xoxb-...` Bot User OAuth token with `chat:write`; `slack-channel-id` must
contain the target Slack channel ID. `slack-webhook-url` is optional fallback.
Keep Slack credential values out of the Codex config and out of Git. Existing
`~/.config/dotfiles/files/codex/slack-*` files are still read as fallback
credentials.

The implementation lives in the Rust `dotfiles` control plane. Codex-specific
hook and transcript parsing is isolated in the Codex adapter; Slack-specific
formatting, posting, thread-state, fallback, and error-log logic is the generic
Slack sink. `scripts/codex-slack-notification` is a compatibility shim that
delegates to `dotfiles agent-notify codex`.

Thread support also requires the Slack app or bot user to be able to post to
the target channel. Invite the bot to private channels. For public channels,
either invite the bot or add `chat:write.public` to the app's bot scopes and
reinstall the app.

The command also accepts these one-off overrides. Legacy `CODEX_SLACK_*` names
remain fallback aliases for the same settings.

- `AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN_FILE` / `AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN`
- `AGENT_NOTIFICATIONS_SLACK_CHANNEL_ID_FILE` / `AGENT_NOTIFICATIONS_SLACK_CHANNEL_ID`
- `AGENT_NOTIFICATIONS_SLACK_WEBHOOK_FILE` / `AGENT_NOTIFICATIONS_SLACK_WEBHOOK_URL`
- `AGENT_NOTIFICATIONS_SLACK_THREAD_STATE_FILE`
- `AGENT_NOTIFICATIONS_DEDUPE_STATE_FILE`
- `AGENT_NOTIFICATIONS_ERROR_LOG_FILE`
- `AGENT_NOTIFICATIONS_INCLUDE_CONTEXT=1`
- `AGENT_NOTIFICATIONS_REPLY_MENTION` (defaults to `<!channel>`; set empty to disable)
- `AGENT_NOTIFICATIONS_REPLY_MENTION_EVENTS` (comma-separated event names)
- `AGENT_NOTIFICATIONS_REPLY_BROADCAST=1`
- `AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1`

Usage:

1. Store Slack credentials locally:

   ```bash
   mkdir -p ~/.config/dotfiles/files/agent-notifications
   printf '%s\n' 'xoxb-...' \
     > ~/.config/dotfiles/files/agent-notifications/slack-bot-token
   printf '%s\n' 'C0123456789' \
     > ~/.config/dotfiles/files/agent-notifications/slack-channel-id
   chmod 0600 \
     ~/.config/dotfiles/files/agent-notifications/slack-bot-token \
     ~/.config/dotfiles/files/agent-notifications/slack-channel-id
   ```

   Optional webhook fallback:

   ```bash
   printf '%s\n' 'https://hooks.slack.com/services/...' \
     > ~/.config/dotfiles/files/agent-notifications/slack-webhook-url
   chmod 0600 ~/.config/dotfiles/files/agent-notifications/slack-webhook-url
   ```

2. Add Codex lifecycle hooks to `~/.codex/config.toml`:

   ```toml
   [features]
   codex_hooks = true

   # Transcript watcher for Codex thread titles, Plan Mode questions, and
   # approval waits, plus completion replies tied to this exact Codex transcript.
   # Auto-resolved request_user_input and approval records are skipped.
   [[hooks.SessionStart]]
   [[hooks.SessionStart.hooks]]
   type = "command"
   command = "/path/to/dotfiles/scripts/codex-slack-notification --spawn-watcher"
   timeout = 5
   statusMessage = "Starting Codex Slack transcript watcher"
   ```

3. Preview the Slack payload without posting:

   ```bash
   dotfiles agent-notify codex --dry-run <<'JSON'
   {
     "hook_event_name": "Stop",
     "cwd": "/path/to/project",
     "last_assistant_message": "Dry-run notification."
   }
   JSON
   ```

Thread state is stored locally at:

```text
~/.local/state/dotfiles/agent-notifications/slack-threads.json
~/.local/state/dotfiles/agent-notifications/codex-dedupe.json
~/.local/state/dotfiles/agent-notifications/slack.log
```

If the new state files do not exist, the command reads the old
`~/.local/state/dotfiles/codex-slack-*` files as fallback state and writes
future updates to the new `agent-notifications` paths.

If Slack returns `channel_not_found`, invite the Slack app or bot user to the
target channel, or use a channel ID from the same workspace installation as the
Bot User OAuth token. Incoming webhook fallback keeps notifications flowing, but
it cannot populate the local `thread_ts` map, so thread support requires
successful `chat.postMessage` calls through the Bot User OAuth token. Bot or
webhook failures are recorded in `slack.log` without writing credential values.

`SessionStart` starts a transcript watcher, and the watcher creates the Slack
parent from Codex's generated `thread_name_updated` title event when available.
Parent messages use `Codex: <title> (<repo>)`. If a title event is unavailable,
the first notification derives a short title from the first user prompt before
falling back to `Codex: <repo>`, and a later title event updates it. The watcher
also posts Plan Mode questions, approval waits, and `task_complete` records from
that exact transcript, so parallel Codex sessions in the same repo do not depend
on "latest session for cwd" inference. Auto-resolved `request_user_input`
records outside Plan Mode are ignored. Approval waits from
`guardian_assessment` records are delayed up to 30 seconds while the watcher
checks for Codex auto-review. Requests that receive an agent `approved` decision
are skipped; requests without an automatic approval still post to Slack.
Actionable or terminal notifications are posted as thread replies with
`<!channel>` by default. They are not broadcast into the channel timeline unless
`AGENT_NOTIFICATIONS_REPLY_BROADCAST=1` is set.

Do not configure `PermissionRequest` by default. Codex renders hook
`statusMessage` values before the helper can inspect the payload, so
auto-resolved permission events can otherwise create UI noise even when no Slack
message is sent. The transcript watcher owns approval notifications in the
recommended setup.

When bot token and channel id are configured, the helper tries threaded Bot API
posting first. If Bot API posting fails, actionable and completion
notifications fall back to the incoming webhook; thread-parent events are
skipped because a webhook message cannot maintain the Codex-to-Slack thread map.
Set `AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT=1` only when you
prefer hard failure over unthreaded best-effort notifications.

4. Send a one-off test notification:

   ```bash
   dotfiles agent-notify test
   ```

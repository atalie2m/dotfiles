#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

if [[ -z ${DOTFILES_BIN:-} ]]; then
  cargo build -p dotfiles-cli >/dev/null
  DOTFILES_BIN="$ROOT/target/debug/dotfiles"
fi

mkdir -p "$TMP_HOME/.config/dotfiles/files/agent-notifications"
printf '%s\n' 'https://example.invalid/slack-webhook' \
  >"$TMP_HOME/.config/dotfiles/files/agent-notifications/slack-webhook-url"
chmod 0600 "$TMP_HOME/.config/dotfiles/files/agent-notifications/slack-webhook-url"

stop_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/tmp/example-project",
  "last_assistant_message": "Done and verified."
}
JSON
)

shim_output=$(
  HOME="$TMP_HOME" DOTFILES_BIN="$DOTFILES_BIN" \
    "$ROOT/scripts/codex-slack-notification" --dry-run <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/tmp/shim-project",
  "last_assistant_message": "Shim complete."
}
JSON
)

legacy_env_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$DOTFILES_BIN" agent-notify codex <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/tmp/legacy-env-project",
  "last_assistant_message": "Legacy env dry run."
}
JSON
)

request_input_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run --event-name RequestUserInput <<'JSON'
{
  "cwd": "/tmp/question-project",
  "tool_name": "request_user_input",
  "tool_input": {
    "questions": [
      {
        "header": "Question",
        "id": "question_test",
        "question": "Which option should I use?",
        "options": [
          {"label": "Yes (Recommended)", "description": "Use the default path."},
          {"label": "No", "description": "Do not continue."}
        ]
      }
    ]
  }
}
JSON
)

request_input_auto_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run --event-name RequestUserInput <<'JSON'
{
  "cwd": "/tmp/question-project",
  "collaboration_mode": {"mode": "default"},
  "tool_name": "request_user_input",
  "tool_input": {
    "questions": [
      {
        "header": "Question",
        "id": "question_test",
        "question": "Which option should I use?",
        "options": [
          {"label": "Yes (Recommended)", "description": "Use the default path."},
          {"label": "No", "description": "Do not continue."}
        ]
      }
    ]
  }
}
JSON
)

if [[ -n $request_input_auto_output ]]; then
  echo "FAIL: auto-resolved RequestUserInput produced Slack payload" >&2
  exit 1
fi

permission_auto_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "PermissionRequest",
  "cwd": "/tmp/approval-project",
  "approval_policy": "never",
  "tool_name": "exec_command",
  "tool_input": {
    "description": "Run a command."
  }
}
JSON
)

if [[ -n $permission_auto_output ]]; then
  echo "FAIL: auto-resolved PermissionRequest produced Slack payload" >&2
  exit 1
fi

prompt_submit_default_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "UserPromptSubmit",
  "cwd": "/tmp/prompt-project",
  "prompt": "Can you check this?"
}
JSON
)

if [[ -n $prompt_submit_default_output ]]; then
  echo "FAIL: UserPromptSubmit produced Slack payload by default" >&2
  exit 1
fi

prompt_submit_enabled_output=$(
  HOME="$TMP_HOME" AGENT_NOTIFICATIONS_NOTIFY_USER_PROMPTS=1 \
    "$DOTFILES_BIN" agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "UserPromptSubmit",
  "cwd": "/tmp/prompt-project",
  "prompt": "Can you check this?"
}
JSON
)

post_tool_success_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "PostToolUse",
  "cwd": "/tmp/success-project",
  "tool_name": "Bash",
  "tool_input": {
    "command": "cargo test"
  },
  "tool_response": {
    "exit_code": 0,
    "stdout": "ok"
  }
}
JSON
)

if [[ -n $post_tool_success_output ]]; then
  echo "FAIL: successful PostToolUse produced Slack payload" >&2
  exit 1
fi

post_tool_failure_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify codex --dry-run <<'JSON'
{
  "hook_event_name": "PostToolUse",
  "cwd": "/tmp/failure-project",
  "tool_name": "Bash",
  "tool_input": {
    "command": "cargo test"
  },
  "tool_response": {
    "exit_code": 1,
    "stderr": "expected true to be false"
  }
}
JSON
)

test_output=$(
  HOME="$TMP_HOME" "$DOTFILES_BIN" agent-notify test --dry-run --cwd /tmp/test-project
)

python3 - \
  "$stop_output" \
  "$shim_output" \
  "$legacy_env_output" \
  "$request_input_output" \
  "$prompt_submit_enabled_output" \
  "$post_tool_failure_output" \
  "$test_output" <<'PY'
import json
import sys

stop_payload = json.loads(sys.argv[1])
shim_payload = json.loads(sys.argv[2])
legacy_env_payload = json.loads(sys.argv[3])
request_input_payload = json.loads(sys.argv[4])
prompt_submit_payload = json.loads(sys.argv[5])
post_tool_failure_payload = json.loads(sys.argv[6])
test_payload = json.loads(sys.argv[7])

assert stop_payload["text"] == "Codex completed: example-project"
assert stop_payload["blocks"][0]["text"]["text"].startswith("<!channel>")
assert stop_payload["blocks"][1]["text"]["text"] == "Done and verified."

assert shim_payload["text"] == "Codex completed: shim-project"
assert shim_payload["blocks"][1]["text"]["text"] == "Shim complete."

assert legacy_env_payload["text"] == "Codex completed: legacy-env-project"
assert legacy_env_payload["blocks"][1]["text"]["text"] == "Legacy env dry run."

assert request_input_payload["text"] == "Codex needs input: question-project"
request_input_text = request_input_payload["blocks"][1]["text"]["text"]
assert "*Question*" in request_input_text
assert "Which option should I use?" in request_input_text
assert "Options: Yes (Recommended), No" in request_input_text

assert prompt_submit_payload["text"] == "User asked Codex: prompt-project"
assert prompt_submit_payload["blocks"][1]["text"]["text"] == "Can you check this?"

assert post_tool_failure_payload["text"] == "Codex tool failed: failure-project"
failure_text = post_tool_failure_payload["blocks"][1]["text"]["text"]
assert "Tool: `Bash`" in failure_text
assert "Command: ```cargo test```" in failure_text
assert "expected true to be false" in failure_text

assert test_payload["text"] == "Agent notification test: test-project"
assert test_payload["blocks"][1]["text"]["text"] == "Agent Slack notification setup test completed."
PY

echo "PASS: codex Slack notification"

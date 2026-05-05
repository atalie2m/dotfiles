#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TMP_HOME=$(mktemp -d)
trap 'rm -rf "$TMP_HOME"' EXIT

mkdir -p "$TMP_HOME/.config/dotfiles/files/codex"
printf '%s\n' 'https://example.invalid/slack-webhook' \
  >"$TMP_HOME/.config/dotfiles/files/codex/slack-webhook-url"
chmod 0600 "$TMP_HOME/.config/dotfiles/files/codex/slack-webhook-url"

stop_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/tmp/example-project",
  "last_assistant_message": "Done and verified."
}
JSON
)

legacy_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" \
    '{"type":"agent-turn-complete","cwd":"/tmp/legacy-project","last-assistant-message":"Legacy complete."}'
)

question_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/tmp/question-project",
  "last_agent_message": "Which option should I use?"
}
JSON
)

request_input_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" --event-name RequestUserInput <<'JSON'
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

prompt_submit_default_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "UserPromptSubmit",
  "cwd": "/tmp/prompt-project",
  "prompt": "Can you check this?"
}
JSON
)

if [[ -n "$prompt_submit_default_output" ]]; then
  echo "FAIL: UserPromptSubmit produced Slack payload by default" >&2
  exit 1
fi

prompt_submit_enabled_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 CODEX_SLACK_NOTIFY_USER_PROMPTS=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "UserPromptSubmit",
  "cwd": "/tmp/prompt-project",
  "prompt": "Can you check this?"
}
JSON
)

internal_prompt_submit_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 CODEX_SLACK_NOTIFY_USER_PROMPTS=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "UserPromptSubmit",
  "cwd": "/tmp/title-project",
  "prompt": "You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title for a task that will be created from that prompt."
}
JSON
)

if [[ -n "$internal_prompt_submit_output" ]]; then
  echo "FAIL: internal title UserPromptSubmit produced Slack payload" >&2
  exit 1
fi

title_generation_stop_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "Stop",
  "cwd": "/tmp/title-project",
  "last_assistant_message": "{\"title\":\"Plan質問をテスト\"}"
}
JSON
)

if [[ -n "$title_generation_stop_output" ]]; then
  echo "FAIL: internal title Stop produced Slack payload" >&2
  exit 1
fi

permission_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "PermissionRequest",
  "cwd": "/tmp/question-project",
  "tool_name": "Bash",
  "tool_input": {
    "description": "Run a command outside the sandbox?",
    "command": "printf test"
  }
}
JSON
)

post_tool_failure_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "PostToolUse",
  "cwd": "/tmp/failure-project",
  "tool_name": "Bash",
  "tool_input": {
    "command": "bun test"
  },
  "tool_response": {
    "exit_code": 1,
    "stderr": "expected true to be false"
  }
}
JSON
)

post_tool_success_output=$(
  HOME="$TMP_HOME" CODEX_SLACK_NOTIFICATION_DRY_RUN=1 \
    "$ROOT/scripts/codex-slack-notification" <<'JSON'
{
  "hook_event_name": "PostToolUse",
  "cwd": "/tmp/success-project",
  "tool_name": "Bash",
  "tool_input": {
    "command": "bun test"
  },
  "tool_response": {
    "exit_code": 0,
    "stdout": "ok"
  }
}
JSON
)

if [[ -n "$post_tool_success_output" ]]; then
  echo "FAIL: successful PostToolUse produced Slack payload" >&2
  exit 1
fi

python3 - \
  "$stop_output" \
  "$legacy_output" \
  "$question_output" \
  "$request_input_output" \
  "$prompt_submit_enabled_output" \
  "$permission_output" \
  "$post_tool_failure_output" <<'PY'
import json
import sys

stop_payload = json.loads(sys.argv[1])
legacy_payload = json.loads(sys.argv[2])
question_payload = json.loads(sys.argv[3])
request_input_payload = json.loads(sys.argv[4])
prompt_submit_payload = json.loads(sys.argv[5])
permission_payload = json.loads(sys.argv[6])
post_tool_failure_payload = json.loads(sys.argv[7])

assert stop_payload["text"] == "Codex completed: example-project"
assert len(stop_payload["blocks"]) == 2
assert stop_payload["blocks"][0]["text"]["text"].startswith("<!channel>")
assert stop_payload["blocks"][1]["text"]["text"] == "Done and verified."

assert legacy_payload["text"] == "Codex completed: legacy-project"
assert "Legacy complete." in legacy_payload["blocks"][1]["text"]["text"]

assert question_payload["text"] == "Codex needs input: question-project"
assert question_payload["blocks"][0]["text"]["text"].startswith("<!channel>")
assert question_payload["blocks"][1]["text"]["text"] == "Which option should I use?"

assert request_input_payload["text"] == "Codex needs input: question-project"
assert request_input_payload["blocks"][0]["text"]["text"].startswith("<!channel>")
request_input_text = request_input_payload["blocks"][1]["text"]["text"]
assert "*Question*" in request_input_text
assert "Which option should I use?" in request_input_text
assert "Options: Yes (Recommended), No" in request_input_text

assert prompt_submit_payload["text"] == "User asked Codex: prompt-project"
assert prompt_submit_payload["blocks"][1]["text"]["text"] == "Can you check this?"

assert permission_payload["text"] == "Codex needs approval: question-project"
assert permission_payload["blocks"][0]["text"]["text"].startswith("<!channel>")
assert "Tool: `Bash`" in permission_payload["blocks"][1]["text"]["text"]
assert "Run a command outside the sandbox?" in permission_payload["blocks"][1]["text"]["text"]

assert post_tool_failure_payload["text"] == "Codex tool failed: failure-project"
assert post_tool_failure_payload["blocks"][0]["text"]["text"].startswith("<!channel>")
assert "Command: ```bun test```" in post_tool_failure_payload["blocks"][1]["text"]["text"]
assert "expected true to be false" in post_tool_failure_payload["blocks"][1]["text"]["text"]
PY

python3 - "$ROOT" "$TMP_HOME" <<'PY'
import json
import os
from pathlib import Path
import runpy
import sys
from types import SimpleNamespace

root = Path(sys.argv[1])
tmp_home = Path(sys.argv[2])
script = runpy.run_path(str(root / "scripts/codex-slack-notification"))
requests = []

transcript = tmp_home / "transcript.jsonl"
transcript.write_text(
    json.dumps(
        {
            "type": "event_msg",
            "payload": {
                "type": "task_complete",
                "last_agent_message": "Should I continue with this plan?",
            },
        }
    )
    + "\n",
    encoding="utf-8",
)

transcript_payload = script["build_slack_payload"](
    {
        "hook_event_name": "Stop",
        "cwd": "/tmp/transcript-project",
        "transcript_path": str(transcript),
    },
    None,
)
assert transcript_payload["text"] == "Codex needs input: transcript-project"
assert (
    transcript_payload["blocks"][1]["text"]["text"]
    == "Should I continue with this plan?"
)


def fake_post_web_api(api_url, bot_token, slack_payload):
    requests.append(slack_payload.copy())
    return {
        "ok": True,
        "channel": slack_payload["channel"],
        "ts": f"111.00000{len(requests)}",
    }


post_threaded = script["post_threaded"]
post_threaded.__globals__["post_web_api"] = fake_post_web_api
state_file = tmp_home / ".local/state/dotfiles/codex-slack-threads.json"
session_id = "019df3f2-315b-7e23-8f91-cb8c05a68ea6"
transcript_path = f"/tmp/rollout-2026-05-05T02-03-49-{session_id}.jsonl"

assert script["session_id_from_transcript_path"](transcript_path) == session_id
assert script["thread_key"]({"transcript_path": transcript_path}) == session_id

inferred_session_id = "019df6aa-1111-7222-8333-123456789abc"
inferred_transcript = (
    tmp_home
    / ".codex/sessions/2026/05/05"
    / f"rollout-2026-05-05T11-30-00-{inferred_session_id}.jsonl"
)
inferred_transcript.parent.mkdir(parents=True, exist_ok=True)
inferred_transcript.write_text(
    json.dumps(
        {
            "type": "turn_context",
            "payload": {
                "cwd": "/tmp/thread-project",
                "turn_id": "turn-1",
            },
        }
    )
    + "\n"
    + json.dumps(
        {
            "type": "event_msg",
            "payload": {
                "type": "thread_name_updated",
                "thread_id": inferred_session_id,
                "thread_name": "Inferred Codex Title",
            },
        }
    )
    + "\n",
    encoding="utf-8",
)
os.environ["HOME"] = str(tmp_home)
assert (
    script["thread_key"]({"hook_event_name": "Stop", "cwd": "/tmp/thread-project"})
    == inferred_session_id
)
assert script["thread_name_from_transcript"](str(inferred_transcript)) == "Inferred Codex Title"
inferred_start = script["thread_start_payload"](
    session_id=inferred_session_id,
    cwd="/tmp/thread-project",
    transcript_path=str(inferred_transcript),
)
assert inferred_start["thread_name"] == "Inferred Codex Title"
assert (
    script["thread_parent_title"](inferred_start)
    == "Codex: Inferred Codex Title (thread-project)"
)

prompt_title_session_id = "019df6ad-1111-7222-8333-123456789abc"
prompt_title_transcript = (
    tmp_home
    / ".codex/sessions/2026/05/05"
    / f"rollout-2026-05-05T11-30-30-{prompt_title_session_id}.jsonl"
)
prompt_title_transcript.write_text(
    json.dumps(
        {
            "type": "event_msg",
            "payload": {
                "type": "user_message",
                "message": (
                    "Slackタイトルfallbackの実動確認テストです。"
                    "ファイル操作やコマンド実行はしないでください。"
                ),
            },
        }
    )
    + "\n"
    + json.dumps(
        {
            "type": "event_msg",
            "payload": {
                "type": "task_complete",
                "turn_id": "turn-prompt-title",
                "last_agent_message": "Fallback title complete.",
            },
        }
    )
    + "\n",
    encoding="utf-8",
)
assert (
    script["thread_parent_title"](
        {
            "hook_event_name": "Stop",
            "cwd": "/tmp/thread-project",
            "transcript_path": str(prompt_title_transcript),
            "last_assistant_message": "Fallback title complete.",
        }
    )
    == "Codex: Slackタイトルfallbackの実動確認テスト (thread-project)"
)

concurrent_cwd = "/tmp/concurrent-project"
old_session_id = "019df6bb-1111-7222-8333-123456789abc"
new_session_id = "019df6cc-1111-7222-8333-123456789abc"
old_transcript = (
    tmp_home
    / ".codex/sessions/2026/05/05"
    / f"rollout-2026-05-05T11-31-00-{old_session_id}.jsonl"
)
new_transcript = (
    tmp_home
    / ".codex/sessions/2026/05/05"
    / f"rollout-2026-05-05T11-32-00-{new_session_id}.jsonl"
)
for path, turn_id, message in (
    (old_transcript, "turn-old", "Old thread completed."),
    (new_transcript, "turn-new", "New thread completed."),
):
    path.write_text(
        json.dumps(
            {
                "type": "turn_context",
                "payload": {
                    "cwd": concurrent_cwd,
                    "turn_id": turn_id,
                },
            }
        )
        + "\n"
        + json.dumps(
            {
                "type": "event_msg",
                "payload": {
                    "type": "task_complete",
                    "turn_id": turn_id,
                    "last_agent_message": message,
                },
            }
        )
        + "\n",
        encoding="utf-8",
    )
os.utime(old_transcript, (1000, 1000))
os.utime(new_transcript, (2000, 2000))

assert (
    script["thread_key"](
        {
            "hook_event_name": "Stop",
            "cwd": concurrent_cwd,
            "last_assistant_message": "Old thread completed.",
        }
    )
    == old_session_id
)
assert (
    script["thread_key"](
        {
            "hook_event_name": "Stop",
            "cwd": concurrent_cwd,
            "last_assistant_message": "New thread completed.",
        }
    )
    == new_session_id
)

request_payload = {
    "session_id": session_id,
    "hook_event_name": "RequestUserInput",
    "cwd": "/tmp/thread-project",
    "tool_use_id": "call_request_input_test",
    "tool_input": {"questions": [{"question": "Choose an option."}]},
}
request_slack_payload = script["build_slack_payload"](request_payload, None)
parent_payload = {
    "session_id": session_id,
    "hook_event_name": "ThreadNameUpdated",
    "cwd": "/tmp/thread-project",
    "thread_name": "Plan質問をテスト",
    "transcript_path": transcript_path,
}
parent_slack_payload = script["build_slack_payload"](parent_payload, None)
stop_payload = {
    "hook_event_name": "Stop",
    "cwd": "/tmp/thread-project",
    "transcript_path": transcript_path,
    "last_assistant_message": "Done.",
}
stop_slack_payload = script["build_slack_payload"](stop_payload, None)
assert parent_slack_payload["text"] == "Codex: Plan質問をテスト (thread-project)"

post_threaded(
    api_url="https://example.test/chat.postMessage",
    update_api_url="https://example.test/chat.update",
    bot_token="xoxb-test",
    channel_id="C123",
    state_file_path=str(state_file),
    payload=parent_payload,
    slack_payload=parent_slack_payload,
)
post_threaded(
    api_url="https://example.test/chat.postMessage",
    update_api_url="https://example.test/chat.update",
    bot_token="xoxb-test",
    channel_id="C123",
    state_file_path=str(state_file),
    payload=request_payload,
    slack_payload=request_slack_payload,
)
post_threaded(
    api_url="https://example.test/chat.postMessage",
    update_api_url="https://example.test/chat.update",
    bot_token="xoxb-test",
    channel_id="C123",
    state_file_path=str(state_file),
    payload=stop_payload,
    slack_payload=stop_slack_payload,
)

assert len(requests) == 3
assert "thread_ts" not in requests[0]
assert requests[1]["thread_ts"] == "111.000001"
assert "reply_broadcast" not in requests[1]
assert requests[2]["thread_ts"] == "111.000001"
assert "reply_broadcast" not in requests[2]

state = json.loads(state_file.read_text())
assert state["threads"][session_id]["thread_ts"] == "111.000001"
assert state["threads"][session_id]["title"] == "Codex: Plan質問をテスト (thread-project)"

requests.clear()
late_title_state_file = tmp_home / ".local/state/dotfiles/codex-slack-late-title.json"
late_title_session_id = "019df6dd-1111-7222-8333-123456789abc"
late_title_request_payload = dict(request_payload)
late_title_request_payload["session_id"] = late_title_session_id
late_title_request_slack_payload = script["build_slack_payload"](
    late_title_request_payload,
    None,
)
late_title_parent_payload = {
    "session_id": late_title_session_id,
    "hook_event_name": "ThreadNameUpdated",
    "cwd": "/tmp/thread-project",
    "thread_name": "Late Codex Title",
    "transcript_path": transcript_path,
}
late_title_parent_slack_payload = script["build_slack_payload"](
    late_title_parent_payload,
    None,
)
post_threaded(
    api_url="https://example.test/chat.postMessage",
    update_api_url="https://example.test/chat.update",
    bot_token="xoxb-test",
    channel_id="C123",
    state_file_path=str(late_title_state_file),
    payload=late_title_request_payload,
    slack_payload=late_title_request_slack_payload,
)
post_threaded(
    api_url="https://example.test/chat.postMessage",
    update_api_url="https://example.test/chat.update",
    bot_token="xoxb-test",
    channel_id="C123",
    state_file_path=str(late_title_state_file),
    payload=late_title_parent_payload,
    slack_payload=late_title_parent_slack_payload,
)
assert len(requests) == 3
assert requests[0]["text"] == "Codex: thread-project"
assert requests[1]["thread_ts"] == "111.000001"
assert requests[2]["text"] == "Codex: Late Codex Title (thread-project)"
assert requests[2]["ts"] == "111.000001"
late_title_state = json.loads(late_title_state_file.read_text())
assert (
    late_title_state["threads"][late_title_session_id]["title"]
    == "Codex: Late Codex Title (thread-project)"
)

spawn_commands = []


class FakePopen:
    def __init__(self, command, **kwargs):
        spawn_commands.append((list(command), dict(kwargs)))


def unexpected_thread_parent(*args, **kwargs):
    raise AssertionError("SessionStart should not create the Slack parent before title discovery")


spawn_args = SimpleNamespace(
    webhook_file="/tmp/webhook",
    bot_token_file="/tmp/bot-token",
    channel_id_file="/tmp/channel-id",
    state_file="/tmp/thread-state.json",
    question_state_file="/tmp/question-state.json",
    error_log_file="/tmp/error.log",
    slack_api_url="https://example.test/chat.postMessage",
    slack_update_api_url="https://example.test/chat.update",
    watch_timeout_seconds=60,
)
script["spawn_question_watcher"].__globals__["subprocess"].Popen = FakePopen
script["spawn_question_watcher"].__globals__["send_thread_parent"] = unexpected_thread_parent
script["spawn_question_watcher"](
    spawn_args,
    {
        "hook_event_name": "SessionStart",
        "cwd": "/tmp/thread-project",
        "session_id": late_title_session_id,
        "transcript_path": transcript_path,
    },
)
assert len(spawn_commands) == 1
assert "--watch-from-start" in spawn_commands[0][0]

fallback_calls = []


def failing_post_threaded(**kwargs):
    raise RuntimeError("channel_not_found")


def fake_post_webhook(webhook_url, slack_payload):
    fallback_calls.append((webhook_url, slack_payload.copy()))


script["send_slack_payload"].__globals__["post_threaded"] = failing_post_threaded
script["send_slack_payload"].__globals__["post_webhook"] = fake_post_webhook
bot_file = tmp_home / ".config/dotfiles/files/codex/slack-bot-token"
channel_file = tmp_home / ".config/dotfiles/files/codex/slack-channel-id"
webhook_file = tmp_home / ".config/dotfiles/files/codex/slack-webhook-url"
bot_file.write_text("xoxb-test\n")
channel_file.write_text("C123\n")
webhook_file.write_text("https://example.invalid/slack-webhook\n")
args = SimpleNamespace(
    bot_token_file=str(bot_file),
    channel_id_file=str(channel_file),
    webhook_file=str(webhook_file),
    error_log_file=str(tmp_home / ".local/state/dotfiles/codex-slack-notification.log"),
    slack_api_url="https://example.test/chat.postMessage",
    slack_update_api_url="https://example.test/chat.update",
    state_file=str(state_file),
)

assert script["send_slack_payload"](args, request_payload, request_slack_payload) is True
assert len(fallback_calls) == 1
error_log = Path(args.error_log_file).read_text(encoding="utf-8")
assert "bot_api_failed: channel_not_found" in error_log

os.environ["CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT"] = "1"
try:
    assert script["send_slack_payload"](args, request_payload, request_slack_payload) is False
finally:
    os.environ.pop("CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT", None)
assert len(fallback_calls) == 1

assert script["send_slack_payload"](args, parent_payload, parent_slack_payload) is False
assert len(fallback_calls) == 1
error_log = Path(args.error_log_file).read_text(encoding="utf-8")
assert "webhook_skipped_for_thread_parent_after_bot_failure" in error_log

notify_state_file = tmp_home / ".local/state/dotfiles/question-notify-state.json"
notify_args = SimpleNamespace(
    dry_run=False,
    question_state_file=str(notify_state_file),
)


def unsent_slack_payload(args, payload, slack_payload):
    return False


script["notify_request_user_input_once"].__globals__[
    "send_slack_payload"
] = unsent_slack_payload
script["notify_request_user_input_once"](
    args=notify_args,
    notification_payload=request_payload,
    transcript_path=transcript,
)
assert not notify_state_file.exists()


def sent_slack_payload(args, payload, slack_payload):
    return True


script["notify_request_user_input_once"].__globals__[
    "send_slack_payload"
] = sent_slack_payload
script["notify_request_user_input_once"](
    args=notify_args,
    notification_payload=request_payload,
    transcript_path=transcript,
)
notify_state = json.loads(notify_state_file.read_text(encoding="utf-8"))
assert len(notify_state["notified"]) == 1

completion_calls = []


def completion_slack_payload(args, payload, slack_payload):
    completion_calls.append((payload.copy(), slack_payload.copy()))
    return True


script["notify_completion_once"].__globals__[
    "send_slack_payload"
] = completion_slack_payload
completion_state_file = tmp_home / ".local/state/dotfiles/completion-notify-state.json"
completion_args = SimpleNamespace(
    dry_run=False,
    question_state_file=str(completion_state_file),
)
completion_payload = script["completion_record_payload"](
    record_payload={
        "type": "task_complete",
        "turn_id": "turn-old",
        "last_agent_message": "Old thread completed.",
    },
    session_id=old_session_id,
    cwd=concurrent_cwd,
    transcript_path=old_transcript,
)
assert completion_payload is not None
script["notify_completion_once"](
    args=completion_args,
    notification_payload=completion_payload,
    transcript_path=old_transcript,
)
script["notify_completion_once"](
    args=completion_args,
    notification_payload={
        "hook_event_name": "Stop",
        "cwd": concurrent_cwd,
        "last_assistant_message": "Old thread completed.",
        "transcript_path": str(old_transcript),
    },
)
assert len(completion_calls) == 1
completion_state = json.loads(completion_state_file.read_text(encoding="utf-8"))
assert len(completion_state["notified"]) == 1
PY

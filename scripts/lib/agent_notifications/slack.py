from collections.abc import Mapping, Sequence
import datetime
import fcntl
import html
import json
import os
from pathlib import Path
import urllib.request


DEFAULT_TIMEOUT_SECONDS = 5
MAX_MESSAGE_LENGTH = 900


def expand_path(path: str) -> Path:
    return Path(os.path.expandvars(os.path.expanduser(path)))


def collapse(text: str) -> str:
    return " ".join(str(text).split())


def truncate(text: str, limit: int = MAX_MESSAGE_LENGTH) -> str:
    text = collapse(text)
    if len(text) <= limit:
        return text
    return f"{text[: limit - 3]}..."


def format_value(value) -> str:
    if isinstance(value, str):
        return value
    if isinstance(value, Sequence) and not isinstance(value, (bytes, bytearray, str)):
        return " ".join(str(item) for item in value)
    if isinstance(value, Mapping):
        return json.dumps(value, ensure_ascii=False, sort_keys=True)
    return str(value)


def slack_escape(text: str) -> str:
    return html.escape(text, quote=False)


def read_secret(path: str, env_name: str) -> str | None:
    env_value = os.environ.get(env_name)
    if env_value:
        return env_value.strip()

    secret_file = expand_path(path)
    try:
        return secret_file.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None


def read_webhook_url(path: str) -> str | None:
    return read_secret(path, "CODEX_SLACK_WEBHOOK_URL")


def channel_mention(default: str = "<!channel>") -> str | None:
    mention = os.environ.get("CODEX_SLACK_REPLY_MENTION", default).strip()
    return mention or None


def should_mention_event(event_name: str, default_events: set[str]) -> bool:
    if os.environ.get("CODEX_SLACK_REPLY_MENTION", "<!channel>").strip() == "":
        return False

    configured = os.environ.get("CODEX_SLACK_REPLY_MENTION_EVENTS")
    if configured:
        mention_events = {item.strip() for item in configured.split(",") if item.strip()}
    else:
        mention_events = default_events

    return event_name in mention_events


def should_broadcast_reply() -> bool:
    return os.environ.get("CODEX_SLACK_REPLY_BROADCAST") == "1"


def include_context() -> bool:
    return os.environ.get("CODEX_SLACK_INCLUDE_CONTEXT") == "1"


def build_thread_parent_payload(
    *,
    title: str,
    cwd: str,
    context_label: str = "Agent thread",
) -> dict:
    blocks = [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*{slack_escape(title)}*",
            },
        }
    ]

    if include_context():
        blocks.append(
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": f"`{slack_escape(cwd)}` | {context_label}",
                    }
                ],
            }
        )

    return {
        "text": title,
        "blocks": blocks,
    }


def build_reply_payload(
    *,
    title: str,
    message: str | None,
    cwd: str,
    event_label: str,
    mention: str | None,
) -> dict:
    title_prefix = f"{mention} " if mention else ""
    blocks = [
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"{title_prefix}*{slack_escape(title)}*",
            },
        }
    ]

    if include_context():
        blocks.append(
            {
                "type": "context",
                "elements": [
                    {
                        "type": "mrkdwn",
                        "text": (
                            f"`{slack_escape(cwd)}`"
                            f" | event: `{slack_escape(event_label)}`"
                        ),
                    }
                ],
            }
        )

    if message:
        blocks.append(
            {
                "type": "section",
                "text": {
                    "type": "mrkdwn",
                    "text": slack_escape(message),
                },
            }
        )

    return {
        "text": title,
        "blocks": blocks,
    }


def empty_thread_state() -> dict:
    return {"version": 1, "threads": {}}


def read_thread_state(state_file: Path) -> dict:
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return empty_thread_state()
    except json.JSONDecodeError:
        return empty_thread_state()

    if not isinstance(state, Mapping):
        return empty_thread_state()

    threads = state.get("threads")
    if not isinstance(threads, Mapping):
        return empty_thread_state()

    return {"version": 1, "threads": dict(threads)}


def write_state(state_file: Path, state: dict) -> None:
    state_file.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = state_file.with_suffix(f"{state_file.suffix}.tmp")
    tmp_path.write_text(json.dumps(state, indent=2, sort_keys=True), encoding="utf-8")
    os.replace(tmp_path, state_file)


def read_dedupe_state(state_file: Path) -> dict:
    try:
        state = json.loads(state_file.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {"version": 1, "notified": {}}
    except json.JSONDecodeError:
        return {"version": 1, "notified": {}}

    if not isinstance(state, Mapping):
        return {"version": 1, "notified": {}}

    notified = state.get("notified")
    if not isinstance(notified, Mapping):
        return {"version": 1, "notified": {}}

    return {"version": 1, "notified": dict(notified)}


def append_error_log(
    *,
    error_log_file: str,
    event_name: str,
    project: str,
    thread_key: str | None,
    message: str,
) -> None:
    if os.environ.get("CODEX_SLACK_DISABLE_ERROR_LOG") == "1":
        return

    entry = {
        "timestamp": datetime.datetime.now(datetime.UTC).isoformat(),
        "event": event_name,
        "project": project,
        "thread_key": thread_key,
        "message": str(message),
    }
    log_file = expand_path(error_log_file)
    try:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        with log_file.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(entry, ensure_ascii=False, sort_keys=True))
            handle.write("\n")
    except OSError:
        return


def post_webhook(webhook_url: str, slack_payload: dict) -> None:
    request = urllib.request.Request(
        webhook_url,
        data=json.dumps(slack_payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
        response.read()


def post_web_api(api_url: str, bot_token: str, slack_payload: dict) -> dict:
    request = urllib.request.Request(
        api_url,
        data=json.dumps(slack_payload).encode("utf-8"),
        headers={
            "Authorization": f"Bearer {bot_token}",
            "Content-Type": "application/json; charset=utf-8",
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=DEFAULT_TIMEOUT_SECONDS) as response:
        body = response.read().decode("utf-8")

    result = json.loads(body)
    if not result.get("ok"):
        raise RuntimeError(f"Slack chat.postMessage failed: {result.get('error', 'unknown')}")
    return result


def post_threaded(
    *,
    api_url: str,
    update_api_url: str,
    bot_token: str,
    channel_id: str,
    state_file_path: str,
    slack_payload: dict,
    thread_key: str | None,
    thread_parent_event: bool,
    parent_title: str,
    parent_cwd: str,
    parent_context_label: str,
    mention_reply: bool,
    broadcast_reply: bool,
    post_api=post_web_api,
) -> bool:
    if not thread_key:
        request_payload = dict(slack_payload)
        request_payload["channel"] = channel_id
        post_api(api_url, bot_token, request_payload)
        return True

    state_file = expand_path(state_file_path)
    lock_file = state_file.with_suffix(f"{state_file.suffix}.lock")
    lock_file.parent.mkdir(parents=True, exist_ok=True)

    with lock_file.open("a+") as lock_handle:
        fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        state = read_thread_state(state_file)
        threads = state.setdefault("threads", {})
        entry = threads.get(thread_key)

        if thread_parent_event:
            parent_payload = dict(slack_payload)
            if isinstance(entry, Mapping) and entry.get("thread_ts"):
                if parent_title and parent_title != entry.get("title"):
                    update_payload = dict(parent_payload)
                    update_payload["channel"] = entry.get("channel", channel_id)
                    update_payload["ts"] = entry["thread_ts"]
                    post_api(update_api_url, bot_token, update_payload)
                    entry = dict(entry)
                    entry["title"] = parent_title
                    entry["updated_at"] = datetime.datetime.now(datetime.UTC).isoformat()
                    threads[thread_key] = entry
                    write_state(state_file, state)
                return True

            parent_payload["channel"] = channel_id
            result = post_api(api_url, bot_token, parent_payload)
            now = datetime.datetime.now(datetime.UTC).isoformat()
            threads[thread_key] = {
                "channel": result.get("channel", channel_id),
                "thread_ts": result["ts"],
                "title": parent_title,
                "created_at": now,
                "updated_at": now,
            }
            write_state(state_file, state)
            return True

        if not isinstance(entry, Mapping) or not entry.get("thread_ts"):
            parent_payload = build_thread_parent_payload(
                title=parent_title,
                cwd=parent_cwd,
                context_label=parent_context_label,
            )
            parent_payload["channel"] = channel_id
            result = post_api(api_url, bot_token, parent_payload)
            now = datetime.datetime.now(datetime.UTC).isoformat()
            entry = {
                "channel": result.get("channel", channel_id),
                "thread_ts": result["ts"],
                "title": parent_title,
                "created_at": now,
                "updated_at": now,
            }
            threads[thread_key] = entry
            write_state(state_file, state)

        request_payload = dict(slack_payload)
        request_payload["channel"] = entry.get("channel", channel_id)
        request_payload["thread_ts"] = entry["thread_ts"]
        if mention_reply and broadcast_reply:
            request_payload["reply_broadcast"] = True

        post_api(api_url, bot_token, request_payload)
        entry = dict(entry)
        entry["updated_at"] = datetime.datetime.now(datetime.UTC).isoformat()
        threads[thread_key] = entry
        write_state(state_file, state)

    return True


def send_payload(
    *,
    bot_token_file: str,
    channel_id_file: str,
    webhook_file: str,
    error_log_file: str,
    api_url: str,
    update_api_url: str,
    state_file_path: str,
    slack_payload: dict,
    event_name: str,
    project: str,
    thread_key: str | None,
    thread_parent_event: bool,
    parent_title: str,
    parent_cwd: str,
    parent_context_label: str,
    mention_reply: bool,
    broadcast_reply: bool,
    debug_label: str,
    post_threaded_func=post_threaded,
    post_webhook_func=post_webhook,
    read_secret_func=read_secret,
    read_webhook_func=read_webhook_url,
    append_error_log_func=append_error_log,
) -> bool:
    bot_token = read_secret_func(bot_token_file, "CODEX_SLACK_BOT_TOKEN")
    channel_id = read_secret_func(channel_id_file, "CODEX_SLACK_CHANNEL_ID")
    bot_error = None
    if bot_token and channel_id:
        try:
            if post_threaded_func(
                api_url=api_url,
                update_api_url=update_api_url,
                bot_token=bot_token,
                channel_id=channel_id,
                state_file_path=state_file_path,
                slack_payload=slack_payload,
                thread_key=thread_key,
                thread_parent_event=thread_parent_event,
                parent_title=parent_title,
                parent_cwd=parent_cwd,
                parent_context_label=parent_context_label,
                mention_reply=mention_reply,
                broadcast_reply=broadcast_reply,
            ):
                return True
            bot_error = RuntimeError("Slack Bot API did not send a threaded notification")
        except Exception as error:
            bot_error = error
            if os.environ.get("CODEX_SLACK_NOTIFICATION_DEBUG") == "1":
                print(f"{debug_label}: {error}", file=os.sys.stderr)
        if bot_error:
            append_error_log_func(
                error_log_file=error_log_file,
                event_name=event_name,
                project=project,
                thread_key=thread_key,
                message=f"bot_api_failed: {bot_error}",
            )
            if os.environ.get("CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT") == "1":
                return False

    webhook_url = read_webhook_func(webhook_file)
    if webhook_url:
        if thread_parent_event:
            if bot_error:
                append_error_log_func(
                    error_log_file=error_log_file,
                    event_name=event_name,
                    project=project,
                    thread_key=thread_key,
                    message="webhook_skipped_for_thread_parent_after_bot_failure",
                )
            return False
        try:
            post_webhook_func(webhook_url, slack_payload)
            return True
        except Exception as error:
            append_error_log_func(
                error_log_file=error_log_file,
                event_name=event_name,
                project=project,
                thread_key=thread_key,
                message=f"webhook_failed: {error}",
            )
            if os.environ.get("CODEX_SLACK_NOTIFICATION_DEBUG") == "1":
                print(f"{debug_label}: {error}", file=os.sys.stderr)
            return False

    if bot_error:
        append_error_log_func(
            error_log_file=error_log_file,
            event_name=event_name,
            project=project,
            thread_key=thread_key,
            message="webhook_missing_after_bot_failure",
        )

    return False

use fs2::FileExt;
use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{BufRead, BufReader, IsTerminal, Read, Seek, SeekFrom, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const DEFAULT_TIMEOUT_SECONDS: u64 = 5;
const MAX_MESSAGE_LENGTH: usize = 900;
const MAX_THREAD_TITLE_LENGTH: usize = 52;
const WATCH_POLL_MILLIS: u64 = 500;
const WATCH_TIMEOUT_SECONDS: f64 = 12.0 * 60.0 * 60.0;
const MAX_TRANSCRIPT_INFERENCE_CANDIDATES: usize = 40;
const TRANSCRIPT_INFERENCE_TAIL_BYTES: u64 = 256 * 1024;

const DEFAULT_BOT_TOKEN_FILE: &str = "~/.config/dotfiles/files/agent-notifications/slack-bot-token";
const DEFAULT_CHANNEL_ID_FILE: &str =
    "~/.config/dotfiles/files/agent-notifications/slack-channel-id";
const DEFAULT_WEBHOOK_FILE: &str = "~/.config/dotfiles/files/agent-notifications/slack-webhook-url";
const LEGACY_BOT_TOKEN_FILE: &str = "~/.config/dotfiles/files/codex/slack-bot-token";
const LEGACY_CHANNEL_ID_FILE: &str = "~/.config/dotfiles/files/codex/slack-channel-id";
const LEGACY_WEBHOOK_FILE: &str = "~/.config/dotfiles/files/codex/slack-webhook-url";

const DEFAULT_THREAD_STATE_FILE: &str =
    "~/.local/state/dotfiles/agent-notifications/slack-threads.json";
const DEFAULT_DEDUPE_STATE_FILE: &str =
    "~/.local/state/dotfiles/agent-notifications/codex-dedupe.json";
const DEFAULT_ERROR_LOG_FILE: &str = "~/.local/state/dotfiles/agent-notifications/slack.log";
const LEGACY_THREAD_STATE_FILE: &str = "~/.local/state/dotfiles/codex-slack-threads.json";
const LEGACY_DEDUPE_STATE_FILE: &str = "~/.local/state/dotfiles/codex-slack-question-watch.json";

const DEFAULT_SLACK_API_URL: &str = "https://slack.com/api/chat.postMessage";
const DEFAULT_SLACK_UPDATE_API_URL: &str = "https://slack.com/api/chat.update";

const THREAD_PARENT_EVENTS: &[&str] = &["ThreadNameUpdated", "ThreadStart", "SessionStart"];
const COMPLETION_EVENTS: &[&str] = &["Stop", "agent-turn-complete"];
const DEFAULT_MENTION_EVENTS: &[&str] = &[
    "PermissionRequest",
    "PostToolUse",
    "RequestUserInput",
    "Stop",
    "agent-turn-complete",
    "request_user_input",
];

#[derive(Clone, Debug, Default)]
pub struct AgentNotifyConfig {
    pub dry_run: bool,
    pub bot_token_file: Option<String>,
    pub channel_id_file: Option<String>,
    pub webhook_file: Option<String>,
    pub state_file: Option<String>,
    pub dedupe_state_file: Option<String>,
    pub error_log_file: Option<String>,
    pub slack_api_url: Option<String>,
    pub slack_update_api_url: Option<String>,
}

impl AgentNotifyConfig {
    pub fn effective_dry_run(&self) -> bool {
        self.dry_run
            || bool_env(
                "AGENT_NOTIFICATIONS_DRY_RUN",
                Some("CODEX_SLACK_NOTIFICATION_DRY_RUN"),
            )
    }
}

#[derive(Clone, Debug, Default)]
pub struct CodexNotifyOptions {
    pub payload_args: Vec<String>,
    pub event_name: Option<String>,
    pub spawn_watcher: bool,
    pub watch_transcript: Option<String>,
    pub watch_from_start: bool,
    pub watch_timeout_seconds: Option<f64>,
    pub session_id: Option<String>,
    pub cwd: Option<String>,
}

#[derive(Clone, Debug, Default)]
pub struct TestNotifyOptions {
    pub cwd: Option<String>,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum AgentEventKind {
    Started,
    Completed,
    NeedsInput,
    NeedsApproval,
    ToolFailed,
    PromptSubmitted,
    Notification,
}

#[derive(Clone, Debug)]
pub struct AgentEvent {
    pub agent: String,
    pub kind: AgentEventKind,
    pub event_name: String,
    pub session_id: Option<String>,
    pub title: Option<String>,
    pub body: Option<String>,
    pub cwd: String,
    pub turn_id: Option<String>,
    pub dedupe_key: Option<String>,
    pub thread_key: Option<String>,
}

#[derive(Clone, Debug)]
struct SlackNotification {
    event: AgentEvent,
    parent_title: String,
    parent_context_label: String,
    reply_title: Option<String>,
    thread_parent_event: bool,
    mention_reply: bool,
    broadcast_reply: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ThreadState {
    version: u8,
    threads: HashMap<String, ThreadEntry>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ThreadEntry {
    channel: String,
    thread_ts: String,
    title: String,
    created_at: String,
    updated_at: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct DedupeState {
    version: u8,
    notified: HashMap<String, String>,
}

trait SlackClient {
    fn post_web_api(
        &self,
        api_url: &str,
        bot_token: &str,
        slack_payload: &Value,
    ) -> Result<Value, String>;

    fn post_webhook(&self, webhook_url: &str, slack_payload: &Value) -> Result<(), String>;
}

struct UreqSlackClient;

impl SlackClient for UreqSlackClient {
    fn post_web_api(
        &self,
        api_url: &str,
        bot_token: &str,
        slack_payload: &Value,
    ) -> Result<Value, String> {
        let agent = ureq::AgentBuilder::new()
            .timeout(Duration::from_secs(DEFAULT_TIMEOUT_SECONDS))
            .build();
        let response = agent
            .post(api_url)
            .set("Authorization", &format!("Bearer {}", bot_token))
            .set("Content-Type", "application/json; charset=utf-8")
            .send_json(slack_payload.clone())
            .map_err(|err| format!("Slack API request failed: {}", err))?;
        let result: Value = response
            .into_json()
            .map_err(|err| format!("failed to decode Slack API response: {}", err))?;
        if !result.get("ok").and_then(Value::as_bool).unwrap_or(false) {
            let error = result
                .get("error")
                .and_then(Value::as_str)
                .unwrap_or("unknown");
            return Err(format!("Slack chat.postMessage failed: {}", error));
        }
        Ok(result)
    }

    fn post_webhook(&self, webhook_url: &str, slack_payload: &Value) -> Result<(), String> {
        let agent = ureq::AgentBuilder::new()
            .timeout(Duration::from_secs(DEFAULT_TIMEOUT_SECONDS))
            .build();
        agent
            .post(webhook_url)
            .set("Content-Type", "application/json")
            .send_json(slack_payload.clone())
            .map_err(|err| format!("Slack webhook request failed: {}", err))?;
        Ok(())
    }
}

pub fn run_codex_notification(
    config: AgentNotifyConfig,
    options: CodexNotifyOptions,
) -> Result<(), String> {
    match run_codex_notification_inner(config, options) {
        Ok(()) => Ok(()),
        Err(err) => {
            if debug_enabled() {
                eprintln!("agent-notify codex: {}", err);
            }
            Ok(())
        }
    }
}

pub fn run_test_notification(
    config: AgentNotifyConfig,
    options: TestNotifyOptions,
) -> Result<(), String> {
    let cwd = options
        .cwd
        .or_else(|| {
            env::current_dir()
                .ok()
                .map(|path| path.display().to_string())
        })
        .unwrap_or_else(|| ".".to_string());
    let project = project_name_from_cwd(&cwd);
    let event = AgentEvent {
        agent: "Agent".to_string(),
        kind: AgentEventKind::Notification,
        event_name: "setup-test".to_string(),
        session_id: None,
        title: None,
        body: Some("Agent Slack notification setup test completed.".to_string()),
        cwd: cwd.clone(),
        turn_id: None,
        dedupe_key: None,
        thread_key: None,
    };
    let notification = SlackNotification {
        event,
        parent_title: format!("Agent: {}", project),
        parent_context_label: "Agent thread".to_string(),
        reply_title: Some(format!("Agent notification test: {}", project)),
        thread_parent_event: false,
        mention_reply: false,
        broadcast_reply: false,
    };
    send_notification(&config, &notification, true).map(|_| ())
}

fn run_codex_notification_inner(
    config: AgentNotifyConfig,
    options: CodexNotifyOptions,
) -> Result<(), String> {
    if let Some(transcript) = options.watch_transcript.as_deref() {
        return watch_transcript_for_codex(&config, &options, transcript);
    }

    let mut payload = read_payload(&options.payload_args)?;
    if let Some(event_name) = options.event_name.as_deref() {
        if value_get(&payload, "hook_event_name").is_none() {
            value_set_string(&mut payload, "hook_event_name", event_name);
        }
    }

    if options.spawn_watcher {
        return spawn_codex_watcher(&config, &options, &payload);
    }

    let event_name = resolved_event_name(&payload, options.event_name.as_deref());
    if COMPLETION_EVENTS.contains(&event_name.as_str()) {
        notify_completion_once(&config, &payload, None)?;
        return Ok(());
    }

    if let Some(notification) =
        codex_notification_from_payload(&payload, options.event_name.as_deref())
    {
        send_notification(&config, &notification, false)?;
    }
    Ok(())
}

fn read_payload(payload_args: &[String]) -> Result<Value, String> {
    let mut raw = String::new();
    let mut stdin = std::io::stdin();
    if !stdin.is_terminal() {
        stdin
            .read_to_string(&mut raw)
            .map_err(|err| format!("failed to read notification payload: {}", err))?;
        raw = raw.trim().to_string();
    }

    if raw.is_empty() {
        for arg in payload_args.iter().rev() {
            let candidate = arg.trim();
            if candidate.starts_with('{') && candidate.ends_with('}') {
                raw = candidate.to_string();
                break;
            }
        }
    }

    if raw.is_empty() {
        return Ok(json!({}));
    }

    let parsed: Value = serde_json::from_str(&raw)
        .map_err(|err| format!("invalid Codex notification JSON: {}", err))?;
    if !parsed.is_object() {
        return Err("invalid Codex notification JSON: expected object".to_string());
    }
    Ok(parsed)
}

fn codex_notification_from_payload(
    payload: &Value,
    event_name_override: Option<&str>,
) -> Option<SlackNotification> {
    let cwd = first_string(payload, &["cwd"]).unwrap_or_else(|| {
        env::current_dir()
            .ok()
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| ".".to_string())
    });
    let project = project_name_from_cwd(&cwd);
    let event_name = resolved_event_name(payload, event_name_override);

    if COMPLETION_EVENTS.contains(&event_name.as_str())
        && looks_like_title_generation_result(&assistant_message(payload))
    {
        return None;
    }

    let thread_key = codex_thread_key(payload);
    let parent_title = codex_parent_title(payload);
    if THREAD_PARENT_EVENTS.contains(&event_name.as_str()) {
        let key = thread_key.clone()?;
        let event = AgentEvent {
            agent: "Codex".to_string(),
            kind: AgentEventKind::Started,
            event_name,
            session_id: Some(key.clone()),
            title: codex_thread_title(payload),
            body: None,
            cwd,
            turn_id: None,
            dedupe_key: None,
            thread_key: Some(key),
        };
        return Some(SlackNotification {
            event,
            parent_title,
            parent_context_label: "Codex thread".to_string(),
            reply_title: None,
            thread_parent_event: true,
            mention_reply: false,
            broadcast_reply: false,
        });
    }

    let (kind, title, message) = match event_name.as_str() {
        "PermissionRequest" => (
            AgentEventKind::NeedsApproval,
            format!("Codex needs approval: {}", project),
            permission_request_message(payload),
        ),
        "PostToolUse" => (
            AgentEventKind::ToolFailed,
            format!("Codex tool failed: {}", project),
            post_tool_use_failure_message(payload)?,
        ),
        "UserPromptSubmit" => {
            if !bool_env(
                "AGENT_NOTIFICATIONS_NOTIFY_USER_PROMPTS",
                Some("CODEX_SLACK_NOTIFY_USER_PROMPTS"),
            ) {
                return None;
            }
            let message = user_prompt_message(payload);
            if looks_like_internal_title_prompt(&message) {
                return None;
            }
            let title = if looks_like_question(&message) {
                format!("User asked Codex: {}", project)
            } else {
                format!("Codex prompt submitted: {}", project)
            };
            (AgentEventKind::PromptSubmitted, title, message)
        }
        "RequestUserInput" | "request_user_input" => (
            AgentEventKind::NeedsInput,
            format!("Codex needs input: {}", project),
            request_user_input_message(payload),
        ),
        "Stop" | "agent-turn-complete" => {
            let message = assistant_message(payload);
            let title = if looks_like_question(&message) {
                format!("Codex needs input: {}", project)
            } else {
                format!("Codex completed: {}", project)
            };
            let kind = if looks_like_question(&message) {
                AgentEventKind::NeedsInput
            } else {
                AgentEventKind::Completed
            };
            (kind, title, message)
        }
        _ => (
            AgentEventKind::Notification,
            format!("Codex notification: {}", project),
            assistant_message(payload),
        ),
    };

    let event = AgentEvent {
        agent: "Codex".to_string(),
        kind,
        event_name: event_name.clone(),
        session_id: thread_key.clone(),
        title: codex_thread_title(payload),
        body: Some(message),
        cwd,
        turn_id: first_string(payload, &["turn_id", "turn-id"]),
        dedupe_key: None,
        thread_key,
    };
    Some(SlackNotification {
        event,
        parent_title,
        parent_context_label: "Codex thread".to_string(),
        reply_title: Some(title),
        thread_parent_event: false,
        mention_reply: should_mention_event(&event_name),
        broadcast_reply: should_broadcast_reply(),
    })
}

fn send_notification(
    config: &AgentNotifyConfig,
    notification: &SlackNotification,
    strict: bool,
) -> Result<bool, String> {
    let client = UreqSlackClient;
    send_notification_with_client(config, notification, strict, &client)
}

fn send_notification_once(
    config: &AgentNotifyConfig,
    notification: &SlackNotification,
    key: &str,
) -> Result<bool, String> {
    let paths = dedupe_state_paths(config);
    let lock_file = state_lock_path(&paths.primary);
    ensure_parent_dir(&lock_file)?;
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(&lock_file)
        .map_err(|err| format!("failed to open {}: {}", lock_file.display(), err))?;
    lock.lock_exclusive()
        .map_err(|err| format!("failed to lock {}: {}", lock_file.display(), err))?;

    let mut state = read_dedupe_state(&paths.primary, paths.legacy.as_deref());
    if state.notified.contains_key(key) {
        return Ok(true);
    }

    let sent = send_notification(config, notification, false)?;
    if sent {
        state.notified.insert(key.to_string(), timestamp_string());
        write_json_state(&paths.primary, &state)?;
    }
    Ok(sent)
}

fn send_notification_with_client<C: SlackClient>(
    config: &AgentNotifyConfig,
    notification: &SlackNotification,
    strict: bool,
    client: &C,
) -> Result<bool, String> {
    let slack_payload = slack_payload(notification);
    if config.effective_dry_run() {
        println!(
            "{}",
            serde_json::to_string(&slack_payload)
                .map_err(|err| format!("failed to encode Slack payload: {}", err))?
        );
        return Ok(true);
    }

    let api_url = config
        .slack_api_url
        .clone()
        .or_else(|| env_value("AGENT_NOTIFICATIONS_SLACK_API_URL"))
        .or_else(|| env_value("CODEX_SLACK_API_URL"))
        .unwrap_or_else(|| DEFAULT_SLACK_API_URL.to_string());
    let update_api_url = config
        .slack_update_api_url
        .clone()
        .or_else(|| env_value("AGENT_NOTIFICATIONS_SLACK_UPDATE_API_URL"))
        .or_else(|| env_value("CODEX_SLACK_UPDATE_API_URL"))
        .unwrap_or_else(|| DEFAULT_SLACK_UPDATE_API_URL.to_string());

    let bot_token = read_secret(
        &[
            "AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN",
            "CODEX_SLACK_BOT_TOKEN",
        ],
        secret_file_candidates(
            config.bot_token_file.as_deref(),
            "AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN_FILE",
            Some("CODEX_SLACK_BOT_TOKEN_FILE"),
            DEFAULT_BOT_TOKEN_FILE,
            Some(LEGACY_BOT_TOKEN_FILE),
        ),
    );
    let channel_id = read_secret(
        &[
            "AGENT_NOTIFICATIONS_SLACK_CHANNEL_ID",
            "CODEX_SLACK_CHANNEL_ID",
        ],
        secret_file_candidates(
            config.channel_id_file.as_deref(),
            "AGENT_NOTIFICATIONS_SLACK_CHANNEL_ID_FILE",
            Some("CODEX_SLACK_CHANNEL_ID_FILE"),
            DEFAULT_CHANNEL_ID_FILE,
            Some(LEGACY_CHANNEL_ID_FILE),
        ),
    );

    let mut bot_error = None;
    if let (Some(bot_token), Some(channel_id)) = (bot_token.as_deref(), channel_id.as_deref()) {
        match post_threaded(
            config,
            client,
            &api_url,
            &update_api_url,
            bot_token,
            channel_id,
            &slack_payload,
            notification,
        ) {
            Ok(true) => return Ok(true),
            Ok(false) => {
                bot_error = Some("Slack Bot API did not send a threaded notification".to_string());
            }
            Err(err) => {
                bot_error = Some(err);
            }
        }
        if let Some(error) = bot_error.as_deref() {
            append_error_log(config, notification, &format!("bot_api_failed: {}", error));
            if bool_env(
                "AGENT_NOTIFICATIONS_DISABLE_WEBHOOK_FALLBACK_WITH_BOT",
                Some("CODEX_SLACK_DISABLE_WEBHOOK_FALLBACK_WITH_BOT"),
            ) {
                return finish_send_failure(strict, error);
            }
        }
    }

    let webhook_url = read_secret(
        &[
            "AGENT_NOTIFICATIONS_SLACK_WEBHOOK_URL",
            "CODEX_SLACK_WEBHOOK_URL",
        ],
        secret_file_candidates(
            config.webhook_file.as_deref(),
            "AGENT_NOTIFICATIONS_SLACK_WEBHOOK_FILE",
            Some("CODEX_SLACK_WEBHOOK_FILE"),
            DEFAULT_WEBHOOK_FILE,
            Some(LEGACY_WEBHOOK_FILE),
        ),
    );

    if let Some(webhook_url) = webhook_url {
        if notification.thread_parent_event {
            if bot_error.is_some() {
                append_error_log(
                    config,
                    notification,
                    "webhook_skipped_for_thread_parent_after_bot_failure",
                );
            }
            return finish_send_failure(strict, "thread parent requires Slack Bot API");
        }
        match client.post_webhook(&webhook_url, &slack_payload) {
            Ok(()) => return Ok(true),
            Err(err) => {
                append_error_log(config, notification, &format!("webhook_failed: {}", err));
                return finish_send_failure(strict, &err);
            }
        }
    }

    if let Some(error) = bot_error.as_deref() {
        append_error_log(config, notification, "webhook_missing_after_bot_failure");
        return finish_send_failure(strict, error);
    }

    append_error_log(config, notification, "missing_slack_destination");
    finish_send_failure(strict, "missing Slack Bot API credentials or webhook URL")
}

fn finish_send_failure(strict: bool, message: &str) -> Result<bool, String> {
    if strict {
        Err(message.to_string())
    } else {
        Ok(false)
    }
}

#[allow(clippy::too_many_arguments)]
fn post_threaded<C: SlackClient>(
    config: &AgentNotifyConfig,
    client: &C,
    api_url: &str,
    update_api_url: &str,
    bot_token: &str,
    channel_id: &str,
    slack_payload: &Value,
    notification: &SlackNotification,
) -> Result<bool, String> {
    let Some(thread_key) = notification.event.thread_key.as_deref() else {
        let request_payload = object_with_fields(
            slack_payload,
            &[("channel", Value::String(channel_id.to_string()))],
        );
        client.post_web_api(api_url, bot_token, &request_payload)?;
        return Ok(true);
    };

    let paths = thread_state_paths(config);
    let lock_file = state_lock_path(&paths.primary);
    ensure_parent_dir(&lock_file)?;
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(&lock_file)
        .map_err(|err| format!("failed to open {}: {}", lock_file.display(), err))?;
    lock.lock_exclusive()
        .map_err(|err| format!("failed to lock {}: {}", lock_file.display(), err))?;

    let mut state = read_thread_state(&paths.primary, paths.legacy.as_deref());
    let existing = state.threads.get(thread_key).cloned();

    if notification.thread_parent_event {
        if let Some(mut entry) = existing {
            if !notification.parent_title.is_empty() && notification.parent_title != entry.title {
                let update_payload = object_with_fields(
                    slack_payload,
                    &[
                        ("channel", Value::String(entry.channel.clone())),
                        ("ts", Value::String(entry.thread_ts.clone())),
                    ],
                );
                client.post_web_api(update_api_url, bot_token, &update_payload)?;
                entry.title = notification.parent_title.clone();
                entry.updated_at = timestamp_string();
                state.threads.insert(thread_key.to_string(), entry);
                write_json_state(&paths.primary, &state)?;
            } else if !paths.primary.is_file() {
                write_json_state(&paths.primary, &state)?;
            }
            return Ok(true);
        }

        let parent_payload = object_with_fields(
            slack_payload,
            &[("channel", Value::String(channel_id.to_string()))],
        );
        let result = client.post_web_api(api_url, bot_token, &parent_payload)?;
        let ts = result
            .get("ts")
            .and_then(Value::as_str)
            .ok_or_else(|| "Slack chat.postMessage response did not include ts".to_string())?;
        let channel = result
            .get("channel")
            .and_then(Value::as_str)
            .unwrap_or(channel_id);
        let now = timestamp_string();
        state.threads.insert(
            thread_key.to_string(),
            ThreadEntry {
                channel: channel.to_string(),
                thread_ts: ts.to_string(),
                title: notification.parent_title.clone(),
                created_at: now.clone(),
                updated_at: now,
            },
        );
        write_json_state(&paths.primary, &state)?;
        return Ok(true);
    }

    let entry = if let Some(entry) = existing {
        entry
    } else {
        let parent_payload = object_with_fields(
            &thread_parent_payload(
                &notification.parent_title,
                &notification.event.cwd,
                &notification.parent_context_label,
            ),
            &[("channel", Value::String(channel_id.to_string()))],
        );
        let result = client.post_web_api(api_url, bot_token, &parent_payload)?;
        let ts = result
            .get("ts")
            .and_then(Value::as_str)
            .ok_or_else(|| "Slack chat.postMessage response did not include ts".to_string())?;
        let channel = result
            .get("channel")
            .and_then(Value::as_str)
            .unwrap_or(channel_id);
        let now = timestamp_string();
        let entry = ThreadEntry {
            channel: channel.to_string(),
            thread_ts: ts.to_string(),
            title: notification.parent_title.clone(),
            created_at: now.clone(),
            updated_at: now,
        };
        state.threads.insert(thread_key.to_string(), entry.clone());
        write_json_state(&paths.primary, &state)?;
        entry
    };

    let mut reply_fields = vec![
        ("channel", Value::String(entry.channel.clone())),
        ("thread_ts", Value::String(entry.thread_ts.clone())),
    ];
    if notification.mention_reply && notification.broadcast_reply {
        reply_fields.push(("reply_broadcast", Value::Bool(true)));
    }
    let request_payload = object_with_fields(slack_payload, &reply_fields);
    client.post_web_api(api_url, bot_token, &request_payload)?;

    if let Some(entry) = state.threads.get_mut(thread_key) {
        entry.updated_at = timestamp_string();
    }
    write_json_state(&paths.primary, &state)?;
    Ok(true)
}

fn slack_payload(notification: &SlackNotification) -> Value {
    if notification.thread_parent_event {
        thread_parent_payload(
            &notification.parent_title,
            &notification.event.cwd,
            &notification.parent_context_label,
        )
    } else {
        reply_payload(notification)
    }
}

fn thread_parent_payload(title: &str, cwd: &str, context_label: &str) -> Value {
    let mut blocks = vec![json!({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": format!("*{}*", slack_escape(title)),
        },
    })];

    if include_context() {
        blocks.push(json!({
            "type": "context",
            "elements": [{
                "type": "mrkdwn",
                "text": format!("`{}` | {}", slack_escape(cwd), context_label),
            }],
        }));
    }

    json!({
        "text": title,
        "blocks": blocks,
    })
}

fn reply_payload(notification: &SlackNotification) -> Value {
    let title = notification
        .reply_title
        .as_deref()
        .unwrap_or(&notification.parent_title);
    let mention = if notification.mention_reply {
        reply_mention()
    } else {
        None
    };
    let title_prefix = mention
        .as_deref()
        .map(|value| format!("{} ", value))
        .unwrap_or_default();
    let mut blocks = vec![json!({
        "type": "section",
        "text": {
            "type": "mrkdwn",
            "text": format!("{}*{}*", title_prefix, slack_escape(title)),
        },
    })];

    if include_context() {
        blocks.push(json!({
            "type": "context",
            "elements": [{
                "type": "mrkdwn",
                "text": format!(
                    "`{}` | event: `{}`",
                    slack_escape(&notification.event.cwd),
                    slack_escape(&notification.event.event_name.replace('-', " ")),
                ),
            }],
        }));
    }

    if let Some(body) = notification
        .event
        .body
        .as_deref()
        .filter(|value| !value.is_empty())
    {
        blocks.push(json!({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": slack_escape(body),
            },
        }));
    }

    json!({
        "text": title,
        "blocks": blocks,
    })
}

fn notify_request_user_input_once(
    config: &AgentNotifyConfig,
    notification_payload: &Value,
    transcript_path: &Path,
) -> Result<(), String> {
    let call_id =
        first_string(notification_payload, &["tool_use_id", "call_id"]).unwrap_or_default();
    if call_id.is_empty() {
        return Ok(());
    }
    let session_id = first_string(notification_payload, &["session_id"]).unwrap_or_default();
    let key = format!("{}:{}:{}", session_id, call_id, transcript_path.display());
    if let Some(notification) = codex_notification_from_payload(notification_payload, None) {
        send_notification_once(config, &notification, &key)?;
    } else {
        mark_dedupe(config, &key)?;
    }
    Ok(())
}

fn notify_completion_once(
    config: &AgentNotifyConfig,
    notification_payload: &Value,
    transcript_path: Option<&Path>,
) -> Result<bool, String> {
    let transcript_path_text = transcript_path
        .map(|path| path.display().to_string())
        .or_else(|| infer_transcript_path(notification_payload))
        .unwrap_or_default();
    let key = completion_state_key(notification_payload, &transcript_path_text);

    let mut payload = notification_payload.clone();
    if !transcript_path_text.is_empty() {
        value_set_string(&mut payload, "transcript_path", &transcript_path_text);
        if let Some(session_id) = session_id_from_transcript_path(&transcript_path_text) {
            if first_string(&payload, &["session_id"]).is_none() {
                value_set_string(&mut payload, "session_id", &session_id);
            }
        }
    }

    let Some(notification) = codex_notification_from_payload(&payload, None) else {
        if let Some(key) = key {
            mark_dedupe(config, &key)?;
        }
        return Ok(true);
    };

    if let Some(key) = key {
        return send_notification_once(config, &notification, &key);
    }
    send_notification(config, &notification, false)
}

fn completion_state_key(notification_payload: &Value, transcript_path: &str) -> Option<String> {
    if transcript_path.is_empty() {
        return None;
    }
    let turn_id = first_string(notification_payload, &["turn_id", "turn-id"]).or_else(|| {
        task_complete_turn_id_from_transcript(
            transcript_path,
            direct_assistant_message_raw(notification_payload).as_deref(),
        )
    })?;
    let session_id = codex_thread_key(notification_payload)
        .or_else(|| session_id_from_transcript_path(transcript_path))
        .unwrap_or_default();
    Some(format!(
        "task_complete:{}:{}:{}",
        session_id, turn_id, transcript_path
    ))
}

fn mark_dedupe(config: &AgentNotifyConfig, key: &str) -> Result<(), String> {
    let paths = dedupe_state_paths(config);
    let lock_file = state_lock_path(&paths.primary);
    ensure_parent_dir(&lock_file)?;
    let lock = OpenOptions::new()
        .create(true)
        .read(true)
        .write(true)
        .open(&lock_file)
        .map_err(|err| format!("failed to open {}: {}", lock_file.display(), err))?;
    lock.lock_exclusive()
        .map_err(|err| format!("failed to lock {}: {}", lock_file.display(), err))?;
    let mut state = read_dedupe_state(&paths.primary, paths.legacy.as_deref());
    state.notified.insert(key.to_string(), timestamp_string());
    write_json_state(&paths.primary, &state)
}

fn watch_transcript_for_codex(
    config: &AgentNotifyConfig,
    options: &CodexNotifyOptions,
    transcript: &str,
) -> Result<(), String> {
    let transcript_path = expand_path(transcript);
    let cwd = options.cwd.clone();
    let session_id = options.session_id.clone();
    let timeout = options
        .watch_timeout_seconds
        .unwrap_or_else(|| {
            env_value("AGENT_NOTIFICATIONS_WATCH_TIMEOUT_SECONDS")
                .or_else(|| env_value("CODEX_SLACK_QUESTION_WATCH_TIMEOUT_SECONDS"))
                .and_then(|value| value.parse::<f64>().ok())
                .unwrap_or(WATCH_TIMEOUT_SECONDS)
        })
        .max(1.0);
    let deadline = Instant::now() + Duration::from_secs_f64(timeout);
    let mut position = if options.watch_from_start {
        0
    } else {
        fs::metadata(&transcript_path)
            .map(|metadata| metadata.len())
            .unwrap_or(0)
    };

    while Instant::now() < deadline {
        let mut lines = Vec::new();
        if let Ok(mut file) = File::open(&transcript_path) {
            if file.seek(SeekFrom::Start(position)).is_ok() {
                let mut reader = BufReader::new(file);
                let mut line = String::new();
                loop {
                    line.clear();
                    match reader.read_line(&mut line) {
                        Ok(0) => break,
                        Ok(_) => lines.push(line.clone()),
                        Err(_) => break,
                    }
                }
                if let Ok(pos) = reader.stream_position() {
                    position = pos;
                }
            }
        }

        for line in lines {
            let Ok(record) = serde_json::from_str::<Value>(&line) else {
                continue;
            };
            let Some(record_payload) = record_payload(&record) else {
                continue;
            };

            if let Some(payload) = request_user_input_record_payload(
                record_payload,
                session_id.as_deref(),
                cwd.as_deref(),
                &transcript_path,
            ) {
                notify_request_user_input_once(config, &payload, &transcript_path)?;
                continue;
            }

            if let Some(payload) = thread_name_record_payload(
                record_payload,
                session_id.as_deref(),
                cwd.as_deref(),
                &transcript_path,
            ) {
                if let Some(notification) = codex_notification_from_payload(&payload, None) {
                    send_notification(config, &notification, false)?;
                }
                continue;
            }

            if let Some(payload) = completion_record_payload(
                record_payload,
                session_id.as_deref(),
                cwd.as_deref(),
                &transcript_path,
            ) {
                notify_completion_once(config, &payload, Some(&transcript_path))?;
            }
        }

        thread::sleep(Duration::from_millis(WATCH_POLL_MILLIS));
    }

    Ok(())
}

fn spawn_codex_watcher(
    config: &AgentNotifyConfig,
    options: &CodexNotifyOptions,
    payload: &Value,
) -> Result<(), String> {
    let Some(transcript_path) = explicit_transcript_path(payload) else {
        return Ok(());
    };
    let watcher_session_id =
        codex_thread_key(payload).or_else(|| session_id_from_transcript_path(&transcript_path));
    let cwd = first_string(payload, &["cwd"])
        .or_else(|| options.cwd.clone())
        .or_else(|| {
            env::current_dir()
                .ok()
                .map(|path| path.display().to_string())
        })
        .unwrap_or_else(|| ".".to_string());
    let exe =
        env::current_exe().map_err(|err| format!("failed to resolve current exe: {}", err))?;
    let mut command = Command::new(exe);
    command
        .arg("agent-notify")
        .arg("codex")
        .arg("--watch-transcript")
        .arg(transcript_path)
        .arg("--watch-from-start")
        .arg("--session-id")
        .arg(watcher_session_id.unwrap_or_default())
        .arg("--cwd")
        .arg(cwd)
        .arg("--watch-timeout-seconds")
        .arg(
            options
                .watch_timeout_seconds
                .unwrap_or(WATCH_TIMEOUT_SECONDS)
                .to_string(),
        );
    append_config_args(&mut command, config);
    command
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .map_err(|err| format!("failed to spawn Codex transcript watcher: {}", err))?;
    Ok(())
}

fn append_config_args(command: &mut Command, config: &AgentNotifyConfig) {
    if let Some(value) = config.webhook_file.as_deref() {
        command.arg("--webhook-file").arg(value);
    }
    if let Some(value) = config.bot_token_file.as_deref() {
        command.arg("--bot-token-file").arg(value);
    }
    if let Some(value) = config.channel_id_file.as_deref() {
        command.arg("--channel-id-file").arg(value);
    }
    if let Some(value) = config.state_file.as_deref() {
        command.arg("--state-file").arg(value);
    }
    if let Some(value) = config.dedupe_state_file.as_deref() {
        command.arg("--dedupe-state-file").arg(value);
    }
    if let Some(value) = config.error_log_file.as_deref() {
        command.arg("--error-log-file").arg(value);
    }
    if let Some(value) = config.slack_api_url.as_deref() {
        command.arg("--slack-api-url").arg(value);
    }
    if let Some(value) = config.slack_update_api_url.as_deref() {
        command.arg("--slack-update-api-url").arg(value);
    }
    if config.dry_run {
        command.arg("--dry-run");
    }
}

fn request_user_input_record_payload(
    record_payload: &Map<String, Value>,
    session_id: Option<&str>,
    cwd: Option<&str>,
    transcript_path: &Path,
) -> Option<Value> {
    if record_payload.get("type").and_then(Value::as_str) != Some("function_call") {
        return None;
    }
    if record_payload.get("name").and_then(Value::as_str) != Some("request_user_input") {
        return None;
    }
    let arguments = record_payload.get("arguments")?.as_str()?;
    let parsed: Value = serde_json::from_str(arguments).ok()?;
    if !parsed.is_object() {
        return None;
    }
    let mut payload = json!({
        "hook_event_name": "RequestUserInput",
        "cwd": cwd.unwrap_or("."),
        "tool_name": "request_user_input",
        "tool_use_id": record_payload.get("call_id").cloned().unwrap_or(Value::Null),
        "tool_input": parsed,
        "transcript_path": transcript_path.display().to_string(),
    });
    if let Some(session_id) = session_id {
        value_set_string(&mut payload, "session_id", session_id);
    }
    Some(payload)
}

fn thread_name_record_payload(
    record_payload: &Map<String, Value>,
    session_id: Option<&str>,
    cwd: Option<&str>,
    transcript_path: &Path,
) -> Option<Value> {
    if record_payload.get("type").and_then(Value::as_str) != Some("thread_name_updated") {
        return None;
    }
    let title = record_payload.get("thread_name")?.as_str()?.trim();
    if title.is_empty() {
        return None;
    }
    let thread_id = record_payload
        .get("thread_id")
        .and_then(Value::as_str)
        .or(session_id);
    let mut payload = json!({
        "hook_event_name": "ThreadNameUpdated",
        "cwd": cwd.unwrap_or("."),
        "thread_name": title,
        "transcript_path": transcript_path.display().to_string(),
    });
    if let Some(thread_id) = thread_id {
        value_set_string(&mut payload, "session_id", thread_id);
    }
    Some(payload)
}

fn completion_record_payload(
    record_payload: &Map<String, Value>,
    session_id: Option<&str>,
    cwd: Option<&str>,
    transcript_path: &Path,
) -> Option<Value> {
    let message = task_complete_message(record_payload)?;
    let mut payload = json!({
        "hook_event_name": "Stop",
        "cwd": cwd.unwrap_or("."),
        "last_agent_message": message,
        "transcript_path": transcript_path.display().to_string(),
    });
    if let Some(session_id) = session_id {
        value_set_string(&mut payload, "session_id", session_id);
    }
    if let Some(turn_id) = record_payload.get("turn_id").and_then(Value::as_str) {
        value_set_string(&mut payload, "turn_id", turn_id);
    }
    Some(payload)
}

fn task_complete_message(record_payload: &Map<String, Value>) -> Option<String> {
    if record_payload.get("type").and_then(Value::as_str) != Some("task_complete") {
        return None;
    }
    first_string_from_map(
        record_payload,
        &["last_agent_message", "last_assistant_message"],
    )
}

fn message_from_transcript(path: Option<&str>) -> Option<String> {
    let path = expand_path(path?);
    let lines = fs::read_to_string(path).ok()?;
    for line in lines.lines().rev() {
        let Ok(record) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(payload) = record_payload(&record) else {
            continue;
        };
        if payload.get("type").and_then(Value::as_str) == Some("task_complete") {
            if let Some(message) = task_complete_message(payload) {
                return Some(message);
            }
        }
        if payload.get("type").and_then(Value::as_str) == Some("message")
            && matches!(
                payload.get("role").and_then(Value::as_str),
                Some("assistant" | "agent")
            )
            && payload.get("phase").and_then(Value::as_str) != Some("commentary")
        {
            if let Some(message) = content_text(payload.get("content")) {
                return Some(message);
            }
        }
        if payload.get("type").and_then(Value::as_str) == Some("agent_message")
            && payload.get("phase").and_then(Value::as_str) != Some("commentary")
        {
            if let Some(message) = payload.get("message").and_then(Value::as_str) {
                return Some(message.to_string());
            }
        }
    }
    None
}

fn direct_assistant_message_raw(payload: &Value) -> Option<String> {
    first_string(
        payload,
        &[
            "last_assistant_message",
            "last-assistant-message",
            "last_agent_message",
            "last-agent-message",
        ],
    )
    .or_else(|| {
        event_string(
            payload,
            &[
                "last_assistant_message",
                "last-assistant-message",
                "last_agent_message",
                "last-agent-message",
            ],
        )
    })
}

fn assistant_message_raw(payload: &Value) -> Option<String> {
    direct_assistant_message_raw(payload).or_else(|| {
        let transcript = infer_transcript_path(payload);
        message_from_transcript(transcript.as_deref())
    })
}

fn assistant_message(payload: &Value) -> String {
    truncate(
        &assistant_message_raw(payload).unwrap_or_else(|| "Codex completed.".to_string()),
        MAX_MESSAGE_LENGTH,
    )
}

fn user_prompt_message(payload: &Value) -> String {
    let prompt = first_string(payload, &["prompt"]).or_else(|| event_string(payload, &["prompt"]));
    truncate(
        &prompt.unwrap_or_else(|| "User submitted a prompt to Codex.".to_string()),
        MAX_MESSAGE_LENGTH,
    )
}

fn request_user_input_args(payload: &Value) -> Option<Value> {
    if let Some(tool_input) =
        value_get(payload, "tool_input").or_else(|| value_get(payload, "tool-input"))
    {
        if let Some(arguments) = tool_input.get("arguments").and_then(Value::as_str) {
            if let Ok(parsed) = serde_json::from_str::<Value>(arguments) {
                if parsed.is_object() {
                    return Some(parsed);
                }
            }
        }
        if tool_input.is_object() {
            return Some(tool_input.clone());
        }
    }

    if let Some(arguments) = value_get(payload, "arguments") {
        if let Some(arguments) = arguments.as_str() {
            if let Ok(parsed) = serde_json::from_str::<Value>(arguments) {
                if parsed.is_object() {
                    return Some(parsed);
                }
            }
        } else if arguments.is_object() {
            return Some(arguments.clone());
        }
    }

    if payload.get("questions").and_then(Value::as_array).is_some() {
        return Some(payload.clone());
    }
    None
}

fn request_user_input_message(payload: &Value) -> String {
    let Some(args) = request_user_input_args(payload) else {
        return "Codex is waiting for your input.".to_string();
    };
    let Some(questions) = args.get("questions").and_then(Value::as_array) else {
        return "Codex is waiting for your input.".to_string();
    };
    let mut lines = Vec::new();
    for (index, question) in questions.iter().enumerate() {
        let Some(question) = question.as_object() else {
            continue;
        };
        let header = question.get("header").and_then(Value::as_str);
        let text = question
            .get("question")
            .and_then(Value::as_str)
            .or(header)
            .map(ToOwned::to_owned)
            .unwrap_or_else(|| format!("Question {}", index + 1));
        if let Some(header) = header {
            if header != text {
                lines.push(format!("*{}*", header));
            }
        }
        lines.push(text);
        if let Some(options) = question.get("options").and_then(Value::as_array) {
            let labels = options
                .iter()
                .filter_map(|option| option.get("label").map(format_value))
                .collect::<Vec<_>>();
            if !labels.is_empty() {
                lines.push(format!("Options: {}", labels.join(", ")));
            }
        }
    }
    truncate(
        &if lines.is_empty() {
            "Codex is waiting for your input.".to_string()
        } else {
            lines.join("\n")
        },
        MAX_MESSAGE_LENGTH,
    )
}

fn permission_request_message(payload: &Value) -> String {
    let tool_name =
        first_string(payload, &["tool_name", "tool-name"]).unwrap_or_else(|| "tool".to_string());
    let description = nested_string(
        payload,
        &[
            &["tool_input", "description"],
            &["tool-input", "description"],
        ],
    );
    let command = nested_string(
        payload,
        &[&["tool_input", "command"], &["tool-input", "command"]],
    );
    let detail = if let Some(description) = description {
        truncate(&description, MAX_MESSAGE_LENGTH)
    } else if let Some(command) = command {
        format!("```{}```", truncate(&command, 700))
    } else {
        "Codex is waiting for approval.".to_string()
    };
    format!("Tool: `{}`\n{}", tool_name, detail)
}

fn post_tool_use_failure_message(payload: &Value) -> Option<String> {
    let response =
        value_get(payload, "tool_response").or_else(|| value_get(payload, "tool-response"))?;
    if !response_indicates_failure(response) {
        return None;
    }
    let tool_name =
        first_string(payload, &["tool_name", "tool-name"]).unwrap_or_else(|| "tool".to_string());
    let mut parts = vec![format!("Tool: `{}`", tool_name)];
    if let Some(command) = extract_tool_command(payload) {
        parts.push(format!("Command: ```{}```", truncate(&command, 500)));
    }
    if let Some(preview) = extract_response_preview(payload) {
        parts.push(format!("Output: ```{}```", truncate(&preview, 700)));
    }
    Some(parts.join("\n"))
}

fn response_indicates_failure(response: &Value) -> bool {
    let Some(response) = response.as_object() else {
        return false;
    };
    for key in ["success", "ok"] {
        if response.get(key).and_then(Value::as_bool) == Some(false) {
            return true;
        }
    }
    for key in ["exit_code", "exitCode", "status_code", "statusCode", "code"] {
        if response
            .get(key)
            .and_then(Value::as_i64)
            .is_some_and(|value| value != 0)
        {
            return true;
        }
    }
    if response
        .get("status")
        .and_then(Value::as_str)
        .is_some_and(|status| {
            matches!(
                status.to_ascii_lowercase().as_str(),
                "error" | "failed" | "failure"
            )
        })
    {
        return true;
    }
    response.get("error").is_some() || response.get("exception").is_some()
}

fn extract_tool_command(payload: &Value) -> Option<String> {
    let tool_input =
        value_get(payload, "tool_input").or_else(|| value_get(payload, "tool-input"))?;
    let Some(input) = tool_input.as_object() else {
        return Some(format_value(tool_input));
    };
    if let Some(value) = first_value_from_map(input, &["command", "cmd", "input"]) {
        return Some(format_value(value));
    }
    if let Some(params) = input.get("params").and_then(Value::as_object) {
        if let Some(value) = first_value_from_map(params, &["command", "cmd"]) {
            return Some(format_value(value));
        }
    }
    if let Some(arguments) = input.get("arguments") {
        if let Some(arguments) = arguments.as_str() {
            if let Ok(parsed) = serde_json::from_str::<Value>(arguments) {
                if let Some(parsed) = parsed.as_object() {
                    if let Some(value) = first_value_from_map(parsed, &["command", "cmd"]) {
                        return Some(format_value(value));
                    }
                }
                return Some(format_value(&parsed));
            }
            return Some(arguments.to_string());
        }
    }
    Some(format_value(tool_input))
}

fn extract_response_preview(payload: &Value) -> Option<String> {
    let response =
        value_get(payload, "tool_response").or_else(|| value_get(payload, "tool-response"))?;
    let Some(response_object) = response.as_object() else {
        return Some(format_value(response));
    };
    for key in [
        "error",
        "exception",
        "message",
        "stderr",
        "output",
        "stdout",
        "output_preview",
        "outputPreview",
    ] {
        if let Some(value) = response_object.get(key).filter(|value| !value.is_null()) {
            if !format_value(value).is_empty() {
                return Some(format_value(value));
            }
        }
    }
    Some(format_value(response))
}

fn codex_parent_title(payload: &Value) -> String {
    let project = project_name(payload);
    if let Some(title) = codex_thread_title(payload) {
        format!("Codex: {} ({})", title, project)
    } else {
        format!("Codex: {}", project)
    }
}

fn codex_thread_title(payload: &Value) -> Option<String> {
    first_string(
        payload,
        &[
            "thread_name",
            "thread-name",
            "title",
            "codex_title",
            "codex-title",
        ],
    )
    .map(|value| collapse(&value))
    .or_else(|| {
        nested_string(
            payload,
            &[
                &["hook_event", "thread_name"],
                &["hook_event", "thread-name"],
                &["hook_event", "title"],
            ],
        )
        .map(|value| collapse(&value))
    })
    .or_else(|| {
        let transcript_path = title_transcript_path(payload);
        thread_name_from_transcript(transcript_path.as_deref())
    })
    .or_else(|| prompt_title(payload))
}

fn prompt_title(payload: &Value) -> Option<String> {
    first_string(payload, &["prompt"])
        .or_else(|| event_string(payload, &["prompt"]))
        .and_then(|message| prompt_title_from_text(&message))
        .or_else(|| {
            let transcript_path = title_transcript_path(payload);
            prompt_title_from_transcript(transcript_path.as_deref())
        })
}

fn prompt_title_from_text(message: &str) -> Option<String> {
    let first_line = message.lines().find(|line| !line.trim().is_empty())?.trim();
    if first_line.starts_with("# AGENTS.md instructions")
        || looks_like_internal_title_prompt(first_line)
    {
        return None;
    }
    let sentence = first_line
        .split(['。', '！', '？', '!', '?'])
        .next()
        .unwrap_or(first_line);
    let mut title = collapse(sentence)
        .trim_matches(|ch: char| {
            ch == ' '
                || ch == '-'
                || ch == ':'
                || ch == '：'
                || ch == ','
                || ch == '、'
                || ch == '。'
                || ch == '！'
                || ch == '？'
                || ch == '!'
                || ch == '?'
                || ch == '"'
                || ch == '\''
                || ch == '`'
                || ch == '「'
                || ch == '」'
        })
        .to_string();
    for suffix in [
        "をしてください",
        "をして下さい",
        "してください",
        "して下さい",
        "お願いします",
        "ください",
        "下さい",
        "です",
        "ます",
    ] {
        if let Some(stripped) = title.strip_suffix(suffix) {
            title = stripped.trim().to_string();
            break;
        }
    }
    if title.chars().count() < 3 {
        return None;
    }
    Some(truncate(&title, MAX_THREAD_TITLE_LENGTH))
}

fn prompt_title_from_transcript(path: Option<&str>) -> Option<String> {
    let path = expand_path(path?);
    let file = File::open(path).ok()?;
    for line in BufReader::new(file).lines().map_while(Result::ok) {
        let Ok(record) = serde_json::from_str::<Value>(&line) else {
            continue;
        };
        let Some(payload) = record_payload(&record) else {
            continue;
        };
        if payload.get("type").and_then(Value::as_str) == Some("user_message") {
            if let Some(message) = payload.get("message").and_then(Value::as_str) {
                if let Some(title) = prompt_title_from_text(message) {
                    return Some(title);
                }
            }
        }
    }
    None
}

fn title_generation_result(message: &str) -> Option<String> {
    let parsed: Value = serde_json::from_str(message).ok()?;
    let object = parsed.as_object()?;
    if object.len() == 1 {
        object
            .get("title")
            .and_then(Value::as_str)
            .map(collapse)
            .filter(|title| !title.is_empty())
    } else {
        None
    }
}

fn looks_like_title_generation_result(message: &str) -> bool {
    title_generation_result(message).is_some()
}

fn looks_like_internal_title_prompt(message: &str) -> bool {
    message.starts_with("You are a helpful assistant. You will be presented with a user prompt,")
}

fn looks_like_question(message: &str) -> bool {
    let stripped = message.trim();
    !stripped.is_empty() && (stripped.ends_with('?') || stripped.ends_with('？'))
}

fn codex_thread_key(payload: &Value) -> Option<String> {
    explicit_thread_key(payload).or_else(|| {
        let transcript_path = infer_transcript_path(payload);
        session_id_from_transcript_path(transcript_path.as_deref()?)
    })
}

fn explicit_thread_key(payload: &Value) -> Option<String> {
    first_string(
        payload,
        &[
            "session_id",
            "session-id",
            "thread_id",
            "thread-id",
            "conversation_id",
            "conversation-id",
        ],
    )
    .or_else(|| {
        nested_string(
            payload,
            &[
                &["hook_event", "session_id"],
                &["hook_event", "session-id"],
                &["hook_event", "thread_id"],
                &["hook_event", "thread-id"],
                &["hook_event", "conversation_id"],
                &["hook_event", "conversation-id"],
            ],
        )
    })
}

fn explicit_transcript_path(payload: &Value) -> Option<String> {
    first_string(payload, &["transcript_path", "transcript-path"]).or_else(|| {
        nested_string(
            payload,
            &[
                &["hook_event", "transcript_path"],
                &["hook_event", "transcript-path"],
                &["session", "transcript_path"],
                &["session", "transcript-path"],
            ],
        )
    })
}

fn title_transcript_path(payload: &Value) -> Option<String> {
    explicit_transcript_path(payload)
        .or_else(|| {
            explicit_thread_key(payload).and_then(|key| transcript_path_for_session_id(&key))
        })
        .or_else(|| infer_transcript_path(payload))
}

fn transcript_path_for_session_id(session_id: &str) -> Option<String> {
    if !is_session_id(session_id) {
        return None;
    }
    let sessions_root = home_dir()?.join(".codex").join("sessions");
    let mut candidates = Vec::new();
    collect_jsonl_files(&sessions_root, &mut candidates).ok()?;
    candidates.retain(|path| {
        path.file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| name.contains(session_id))
    });
    candidates.sort_by_key(|path| fs::metadata(path).and_then(|m| m.modified()).ok());
    candidates.reverse();
    candidates.first().map(|path| path.display().to_string())
}

fn infer_transcript_path(payload: &Value) -> Option<String> {
    if let Some(path) = explicit_transcript_path(payload) {
        return Some(path);
    }
    let cwd = first_string(payload, &["cwd"]).or_else(|| event_string(payload, &["cwd"]));
    let message = direct_assistant_message_raw(payload);
    let sessions_root = home_dir()?.join(".codex").join("sessions");
    let mut candidates = Vec::new();
    collect_jsonl_files(&sessions_root, &mut candidates).ok()?;
    candidates.sort_by_key(|path| fs::metadata(path).and_then(|m| m.modified()).ok());
    candidates.reverse();

    let mut cwd_matches = Vec::new();
    for candidate in candidates
        .into_iter()
        .take(MAX_TRANSCRIPT_INFERENCE_CANDIDATES)
    {
        if cwd.is_none() && message.is_none() {
            return Some(candidate.display().to_string());
        }
        let tail = transcript_tail(&candidate, TRANSCRIPT_INFERENCE_TAIL_BYTES);
        if let Some(cwd) = cwd.as_deref() {
            if !tail.contains(cwd) {
                continue;
            }
        }
        if let Some(message) = message.as_deref() {
            if task_complete_turn_id_from_transcript(
                &candidate.display().to_string(),
                Some(message),
            )
            .is_some()
            {
                return Some(candidate.display().to_string());
            }
        }
        cwd_matches.push(candidate);
    }
    cwd_matches.first().map(|path| path.display().to_string())
}

fn thread_name_from_transcript(path: Option<&str>) -> Option<String> {
    let path = expand_path(path?);
    for line in transcript_tail(&path, TRANSCRIPT_INFERENCE_TAIL_BYTES)
        .lines()
        .rev()
    {
        let Ok(record) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(payload) = record_payload(&record) else {
            continue;
        };
        if payload.get("type").and_then(Value::as_str) == Some("thread_name_updated") {
            if let Some(title) = payload.get("thread_name").and_then(Value::as_str) {
                let title = collapse(title);
                if !title.is_empty() {
                    return Some(title);
                }
            }
        }
    }
    None
}

fn task_complete_turn_id_from_transcript(path: &str, message: Option<&str>) -> Option<String> {
    let expected = message.map(collapse);
    let path = expand_path(path);
    for line in transcript_tail(&path, TRANSCRIPT_INFERENCE_TAIL_BYTES)
        .lines()
        .rev()
    {
        let Ok(record) = serde_json::from_str::<Value>(line) else {
            continue;
        };
        let Some(payload) = record_payload(&record) else {
            continue;
        };
        if payload.get("type").and_then(Value::as_str) != Some("task_complete") {
            continue;
        }
        if let Some(expected) = expected.as_deref() {
            let candidate = task_complete_message(payload)?;
            if collapse(&candidate) != expected {
                continue;
            }
        }
        if let Some(turn_id) = payload.get("turn_id").and_then(Value::as_str) {
            return Some(turn_id.to_string());
        }
    }
    None
}

fn transcript_tail(path: &Path, limit: u64) -> String {
    let Ok(mut file) = File::open(path) else {
        return String::new();
    };
    let size = file.metadata().map(|metadata| metadata.len()).unwrap_or(0);
    if size > limit && file.seek(SeekFrom::Start(size - limit)).is_err() {
        return String::new();
    }
    let mut bytes = Vec::new();
    if file.read_to_end(&mut bytes).is_err() {
        return String::new();
    }
    String::from_utf8_lossy(&bytes).to_string()
}

fn collect_jsonl_files(dir: &Path, out: &mut Vec<PathBuf>) -> Result<(), String> {
    let entries =
        fs::read_dir(dir).map_err(|err| format!("failed to read {}: {}", dir.display(), err))?;
    for entry in entries {
        let entry =
            entry.map_err(|err| format!("failed to read {} entry: {}", dir.display(), err))?;
        let path = entry.path();
        if path.is_dir() {
            let _ = collect_jsonl_files(&path, out);
        } else if path.extension().and_then(|ext| ext.to_str()) == Some("jsonl") {
            out.push(path);
        }
    }
    Ok(())
}

fn session_id_from_transcript_path(transcript_path: &str) -> Option<String> {
    let name = Path::new(transcript_path).file_name()?.to_str()?;
    let regex = Regex::new(
        r"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?:\.jsonl)?$",
    )
    .ok()?;
    regex
        .captures(name)
        .and_then(|captures| captures.get(1).map(|value| value.as_str().to_string()))
}

fn is_session_id(value: &str) -> bool {
    Regex::new(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
        .map(|regex| regex.is_match(value))
        .unwrap_or(false)
}

fn resolved_event_name(payload: &Value, event_name_override: Option<&str>) -> String {
    event_name_override
        .map(ToOwned::to_owned)
        .or_else(|| first_string(payload, &["hook_event_name", "hook-event-name", "type"]))
        .unwrap_or_else(|| "codex-notification".to_string())
}

fn project_name(payload: &Value) -> String {
    project_name_from_cwd(&first_string(payload, &["cwd"]).unwrap_or_else(|| {
        env::current_dir()
            .ok()
            .map(|path| path.display().to_string())
            .unwrap_or_else(|| ".".to_string())
    }))
}

fn project_name_from_cwd(cwd: &str) -> String {
    Path::new(cwd)
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| !name.is_empty())
        .unwrap_or("unknown")
        .to_string()
}

fn content_text(content: Option<&Value>) -> Option<String> {
    match content? {
        Value::String(text) => Some(text.clone()),
        Value::Array(items) => {
            let parts = items
                .iter()
                .filter_map(|item| {
                    let item = item.as_object()?;
                    let item_type = item.get("type").and_then(Value::as_str)?;
                    if matches!(item_type, "output_text" | "text" | "input_text") {
                        item.get("text")
                            .and_then(Value::as_str)
                            .map(ToOwned::to_owned)
                    } else {
                        None
                    }
                })
                .collect::<Vec<_>>();
            if parts.is_empty() {
                None
            } else {
                Some(parts.join("\n"))
            }
        }
        _ => None,
    }
}

fn record_payload(record: &Value) -> Option<&Map<String, Value>> {
    record.get("payload").and_then(Value::as_object)
}

fn first_value_from_map<'a>(map: &'a Map<String, Value>, keys: &[&str]) -> Option<&'a Value> {
    keys.iter()
        .filter_map(|key| map.get(*key))
        .find(|value| !value.is_null() && value.as_str() != Some(""))
}

fn first_string_from_map(map: &Map<String, Value>, keys: &[&str]) -> Option<String> {
    first_value_from_map(map, keys).and_then(value_to_nonempty_string)
}

fn first_string(payload: &Value, keys: &[&str]) -> Option<String> {
    let map = payload.as_object()?;
    first_string_from_map(map, keys)
}

fn event_string(payload: &Value, keys: &[&str]) -> Option<String> {
    let event = payload.get("hook_event").and_then(Value::as_object)?;
    first_string_from_map(event, keys)
}

fn nested_string(payload: &Value, paths: &[&[&str]]) -> Option<String> {
    for path in paths {
        let mut value = payload;
        for key in *path {
            value = value.get(*key)?;
        }
        if let Some(text) = value_to_nonempty_string(value) {
            return Some(text);
        }
    }
    None
}

fn value_get<'a>(payload: &'a Value, key: &str) -> Option<&'a Value> {
    payload
        .as_object()
        .and_then(|map| map.get(key))
        .filter(|value| !value.is_null())
}

fn value_to_nonempty_string(value: &Value) -> Option<String> {
    match value {
        Value::String(text) if !text.is_empty() => Some(text.clone()),
        Value::Null => None,
        other => {
            let formatted = format_value(other);
            if formatted.is_empty() {
                None
            } else {
                Some(formatted)
            }
        }
    }
}

fn value_set_string(value: &mut Value, key: &str, text: &str) {
    if let Some(map) = value.as_object_mut() {
        map.insert(key.to_string(), Value::String(text.to_string()));
    }
}

fn object_with_fields(payload: &Value, fields: &[(&str, Value)]) -> Value {
    let mut object = payload.as_object().cloned().unwrap_or_default();
    for (key, value) in fields {
        object.insert((*key).to_string(), value.clone());
    }
    Value::Object(object)
}

fn format_value(value: &Value) -> String {
    match value {
        Value::String(text) => text.clone(),
        Value::Array(items) => items.iter().map(format_value).collect::<Vec<_>>().join(" "),
        Value::Object(_) => serde_json::to_string(value).unwrap_or_else(|_| value.to_string()),
        Value::Null => String::new(),
        other => other.to_string(),
    }
}

fn collapse(text: &str) -> String {
    text.split_whitespace().collect::<Vec<_>>().join(" ")
}

fn truncate(text: &str, limit: usize) -> String {
    let text = collapse(text);
    if text.chars().count() <= limit {
        return text;
    }
    let prefix = text
        .chars()
        .take(limit.saturating_sub(3))
        .collect::<String>();
    format!("{}...", prefix)
}

fn slack_escape(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
}

fn include_context() -> bool {
    bool_env(
        "AGENT_NOTIFICATIONS_INCLUDE_CONTEXT",
        Some("CODEX_SLACK_INCLUDE_CONTEXT"),
    )
}

fn reply_mention() -> Option<String> {
    let value = env_value("AGENT_NOTIFICATIONS_REPLY_MENTION")
        .or_else(|| env_value("CODEX_SLACK_REPLY_MENTION"))
        .unwrap_or_else(|| "<!channel>".to_string());
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

fn should_mention_event(event_name: &str) -> bool {
    if reply_mention().is_none() {
        return false;
    }
    let configured = env_value("AGENT_NOTIFICATIONS_REPLY_MENTION_EVENTS")
        .or_else(|| env_value("CODEX_SLACK_REPLY_MENTION_EVENTS"));
    if let Some(configured) = configured {
        configured
            .split(',')
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .any(|item| item == event_name)
    } else {
        DEFAULT_MENTION_EVENTS.contains(&event_name)
    }
}

fn should_broadcast_reply() -> bool {
    bool_env(
        "AGENT_NOTIFICATIONS_REPLY_BROADCAST",
        Some("CODEX_SLACK_REPLY_BROADCAST"),
    )
}

fn bool_env(primary: &str, legacy: Option<&str>) -> bool {
    env_value(primary)
        .or_else(|| legacy.and_then(env_value))
        .is_some_and(|value| matches!(value.as_str(), "1" | "true" | "TRUE" | "yes" | "YES"))
}

fn debug_enabled() -> bool {
    bool_env(
        "AGENT_NOTIFICATIONS_DEBUG",
        Some("CODEX_SLACK_NOTIFICATION_DEBUG"),
    )
}

fn env_value(name: &str) -> Option<String> {
    env::var(name).ok().filter(|value| !value.is_empty())
}

fn read_secret(env_names: &[&str], file_candidates: Vec<PathBuf>) -> Option<String> {
    for name in env_names {
        if let Some(value) = env_value(name).map(|value| value.trim().to_string()) {
            if !value.is_empty() {
                return Some(value);
            }
        }
    }
    for path in file_candidates {
        if let Ok(value) = fs::read_to_string(path) {
            let value = value.trim().to_string();
            if !value.is_empty() {
                return Some(value);
            }
        }
    }
    None
}

fn secret_file_candidates(
    explicit: Option<&str>,
    primary_env: &str,
    legacy_env: Option<&str>,
    default_path: &str,
    legacy_path: Option<&str>,
) -> Vec<PathBuf> {
    let mut candidates = Vec::new();
    if let Some(explicit) = explicit {
        candidates.push(expand_path(explicit));
        return candidates;
    }
    if let Some(path) = env_value(primary_env) {
        candidates.push(expand_path(&path));
    }
    if let Some(legacy_env) = legacy_env {
        if let Some(path) = env_value(legacy_env) {
            candidates.push(expand_path(&path));
        }
    }
    candidates.push(expand_path(default_path));
    if let Some(legacy_path) = legacy_path {
        candidates.push(expand_path(legacy_path));
    }
    candidates
}

struct StatePaths {
    primary: PathBuf,
    legacy: Option<PathBuf>,
}

fn thread_state_paths(config: &AgentNotifyConfig) -> StatePaths {
    if let Some(path) = config.state_file.as_deref() {
        return StatePaths {
            primary: expand_path(path),
            legacy: None,
        };
    }
    StatePaths {
        primary: env_value("AGENT_NOTIFICATIONS_SLACK_THREAD_STATE_FILE")
            .or_else(|| env_value("CODEX_SLACK_THREAD_STATE_FILE"))
            .map(|path| expand_path(&path))
            .unwrap_or_else(|| expand_path(DEFAULT_THREAD_STATE_FILE)),
        legacy: Some(expand_path(LEGACY_THREAD_STATE_FILE)),
    }
}

fn dedupe_state_paths(config: &AgentNotifyConfig) -> StatePaths {
    if let Some(path) = config.dedupe_state_file.as_deref() {
        return StatePaths {
            primary: expand_path(path),
            legacy: None,
        };
    }
    StatePaths {
        primary: env_value("AGENT_NOTIFICATIONS_DEDUPE_STATE_FILE")
            .or_else(|| env_value("CODEX_SLACK_QUESTION_STATE_FILE"))
            .map(|path| expand_path(&path))
            .unwrap_or_else(|| expand_path(DEFAULT_DEDUPE_STATE_FILE)),
        legacy: Some(expand_path(LEGACY_DEDUPE_STATE_FILE)),
    }
}

fn error_log_file(config: &AgentNotifyConfig) -> PathBuf {
    if let Some(path) = config.error_log_file.as_deref() {
        return expand_path(path);
    }
    env_value("AGENT_NOTIFICATIONS_ERROR_LOG_FILE")
        .or_else(|| env_value("CODEX_SLACK_ERROR_LOG_FILE"))
        .map(|path| expand_path(&path))
        .unwrap_or_else(|| expand_path(DEFAULT_ERROR_LOG_FILE))
}

fn read_thread_state(primary: &Path, legacy: Option<&Path>) -> ThreadState {
    read_json_state::<ThreadState>(primary)
        .or_else(|| {
            if primary.is_file() {
                None
            } else {
                legacy.and_then(read_json_state::<ThreadState>)
            }
        })
        .unwrap_or_else(|| ThreadState {
            version: 1,
            threads: HashMap::new(),
        })
}

fn read_dedupe_state(primary: &Path, legacy: Option<&Path>) -> DedupeState {
    read_json_state::<DedupeState>(primary)
        .or_else(|| {
            if primary.is_file() {
                None
            } else {
                legacy.and_then(read_json_state::<DedupeState>)
            }
        })
        .unwrap_or_else(|| DedupeState {
            version: 1,
            notified: HashMap::new(),
        })
}

fn read_json_state<T: for<'de> Deserialize<'de>>(path: &Path) -> Option<T> {
    let text = fs::read_to_string(path).ok()?;
    serde_json::from_str(&text).ok()
}

fn write_json_state<T: Serialize>(path: &Path, state: &T) -> Result<(), String> {
    ensure_parent_dir(path)?;
    let tmp_path = path.with_extension(format!(
        "{}tmp",
        path.extension()
            .and_then(|extension| extension.to_str())
            .map(|extension| format!("{}.", extension))
            .unwrap_or_default()
    ));
    let text = serde_json::to_string_pretty(state)
        .map_err(|err| format!("failed to encode {}: {}", path.display(), err))?;
    fs::write(&tmp_path, text)
        .map_err(|err| format!("failed to write {}: {}", tmp_path.display(), err))?;
    fs::rename(&tmp_path, path)
        .map_err(|err| format!("failed to replace {}: {}", path.display(), err))
}

fn state_lock_path(path: &Path) -> PathBuf {
    PathBuf::from(format!("{}.lock", path.display()))
}

fn ensure_parent_dir(path: &Path) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("failed to create {}: {}", parent.display(), err))?;
    }
    Ok(())
}

fn append_error_log(config: &AgentNotifyConfig, notification: &SlackNotification, message: &str) {
    if bool_env(
        "AGENT_NOTIFICATIONS_DISABLE_ERROR_LOG",
        Some("CODEX_SLACK_DISABLE_ERROR_LOG"),
    ) {
        return;
    }
    let entry = json!({
        "timestamp": timestamp_string(),
        "event": notification.event.event_name,
        "agent": notification.event.agent,
        "project": project_name_from_cwd(&notification.event.cwd),
        "thread_key": notification.event.thread_key,
        "message": message,
    });
    let path = error_log_file(config);
    if ensure_parent_dir(&path).is_err() {
        return;
    }
    if let Ok(mut file) = OpenOptions::new().create(true).append(true).open(path) {
        let _ = writeln!(
            file,
            "{}",
            serde_json::to_string(&entry).unwrap_or_else(|_| "{}".to_string())
        );
    }
}

fn timestamp_string() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs().to_string())
        .unwrap_or_else(|_| "0".to_string())
}

fn expand_path(path: &str) -> PathBuf {
    let mut text = path.to_string();
    if let Some(home) = env_value("HOME") {
        if text == "~" {
            text = home.clone();
        } else if let Some(rest) = text.strip_prefix("~/") {
            text = format!("{}/{}", home, rest);
        }
        text = text.replace("${HOME}", &home).replace("$HOME", &home);
    }
    PathBuf::from(text)
}

fn home_dir() -> Option<PathBuf> {
    env_value("HOME").map(PathBuf::from)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use tempfile::tempdir;

    struct FakeSlackClient {
        api_results: RefCell<Vec<Value>>,
        api_payloads: RefCell<Vec<Value>>,
        webhook_payloads: RefCell<Vec<Value>>,
        fail_api: bool,
    }

    impl FakeSlackClient {
        fn new() -> Self {
            Self {
                api_results: RefCell::new(Vec::new()),
                api_payloads: RefCell::new(Vec::new()),
                webhook_payloads: RefCell::new(Vec::new()),
                fail_api: false,
            }
        }
    }

    impl SlackClient for FakeSlackClient {
        fn post_web_api(
            &self,
            _api_url: &str,
            _bot_token: &str,
            slack_payload: &Value,
        ) -> Result<Value, String> {
            if self.fail_api {
                return Err("api failed".to_string());
            }
            self.api_payloads.borrow_mut().push(slack_payload.clone());
            let ts = format!("111.00000{}", self.api_payloads.borrow().len());
            let result = json!({
                "ok": true,
                "channel": slack_payload.get("channel").and_then(Value::as_str).unwrap_or("C123"),
                "ts": ts,
            });
            self.api_results.borrow_mut().push(result.clone());
            Ok(result)
        }

        fn post_webhook(&self, _webhook_url: &str, slack_payload: &Value) -> Result<(), String> {
            self.webhook_payloads
                .borrow_mut()
                .push(slack_payload.clone());
            Ok(())
        }
    }

    #[test]
    fn builds_codex_completion_payload() {
        let payload = json!({
            "hook_event_name": "Stop",
            "cwd": "/tmp/example-project",
            "last_assistant_message": "Done and verified."
        });
        let notification = codex_notification_from_payload(&payload, None).expect("notification");
        let slack = slack_payload(&notification);
        assert_eq!(slack["text"], "Codex completed: example-project");
        assert!(slack["blocks"][0]["text"]["text"]
            .as_str()
            .expect("title")
            .starts_with("<!channel>"));
        assert_eq!(slack["blocks"][1]["text"]["text"], "Done and verified.");
    }

    #[test]
    fn formats_request_user_input() {
        let payload = json!({
            "hook_event_name": "RequestUserInput",
            "cwd": "/tmp/question-project",
            "tool_name": "request_user_input",
            "tool_input": {
                "questions": [{
                    "header": "Question",
                    "question": "Which option should I use?",
                    "options": [
                        {"label": "Yes (Recommended)", "description": "Use default."},
                        {"label": "No", "description": "Stop."}
                    ]
                }]
            }
        });
        let notification = codex_notification_from_payload(&payload, None).expect("notification");
        let slack = slack_payload(&notification);
        assert_eq!(slack["text"], "Codex needs input: question-project");
        let body = slack["blocks"][1]["text"]["text"].as_str().expect("body");
        assert!(body.contains("*Question*"));
        assert!(body.contains("Which option should I use?"));
        assert!(body.contains("Options: Yes (Recommended), No"));
    }

    #[test]
    fn filters_successful_tools_and_internal_title_prompts() {
        let success = json!({
            "hook_event_name": "PostToolUse",
            "cwd": "/tmp/success-project",
            "tool_name": "Bash",
            "tool_input": {"command": "cargo test"},
            "tool_response": {"exit_code": 0, "stdout": "ok"}
        });
        assert!(codex_notification_from_payload(&success, None).is_none());

        let internal_prompt = json!({
            "hook_event_name": "UserPromptSubmit",
            "cwd": "/tmp/title-project",
            "prompt": "You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title."
        });
        assert!(codex_notification_from_payload(&internal_prompt, None).is_none());

        let title_result = json!({
            "hook_event_name": "Stop",
            "cwd": "/tmp/title-project",
            "last_assistant_message": "{\"title\":\"Plan質問をテスト\"}"
        });
        assert!(codex_notification_from_payload(&title_result, None).is_none());
    }

    #[test]
    fn derives_thread_title_from_transcript_and_prompt() {
        let temp = tempdir().expect("tempdir");
        let transcript = temp
            .path()
            .join("rollout-2026-05-05T11-30-00-019df6aa-1111-7222-8333-123456789abc.jsonl");
        fs::write(
            &transcript,
            format!(
                "{}\n{}\n",
                json!({
                    "type": "event_msg",
                    "payload": {
                        "type": "user_message",
                        "message": "Slackタイトルfallbackの実動確認テストです。"
                    }
                }),
                json!({
                    "type": "event_msg",
                    "payload": {
                        "type": "thread_name_updated",
                        "thread_id": "019df6aa-1111-7222-8333-123456789abc",
                        "thread_name": "Inferred Codex Title"
                    }
                })
            ),
        )
        .expect("write transcript");
        let payload = json!({
            "hook_event_name": "ThreadNameUpdated",
            "cwd": "/tmp/thread-project",
            "transcript_path": transcript.display().to_string(),
            "session_id": "019df6aa-1111-7222-8333-123456789abc"
        });
        assert_eq!(
            codex_parent_title(&payload),
            "Codex: Inferred Codex Title (thread-project)"
        );
    }

    #[test]
    fn prefers_new_credentials_then_legacy_credentials() {
        let temp = tempdir().expect("tempdir");
        let new_file = temp.path().join("new-token");
        let old_file = temp.path().join("old-token");
        fs::write(&new_file, "xoxb-new\n").expect("write new");
        fs::write(&old_file, "xoxb-old\n").expect("write old");
        let value = read_secret(
            &["AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN_TEST"],
            vec![new_file.clone(), old_file.clone()],
        );
        assert_eq!(value.as_deref(), Some("xoxb-new"));
        fs::remove_file(new_file).expect("remove new");
        let value = read_secret(
            &["AGENT_NOTIFICATIONS_SLACK_BOT_TOKEN_TEST"],
            vec![temp.path().join("missing"), old_file],
        );
        assert_eq!(value.as_deref(), Some("xoxb-old"));
    }

    #[test]
    fn posts_thread_parent_then_reply_and_updates_state() {
        let temp = tempdir().expect("tempdir");
        let bot_token_file = temp.path().join("bot-token");
        let channel_id_file = temp.path().join("channel-id");
        fs::write(&bot_token_file, "xoxb-test\n").expect("bot token");
        fs::write(&channel_id_file, "C123\n").expect("channel id");
        let config = AgentNotifyConfig {
            bot_token_file: Some(bot_token_file.display().to_string()),
            channel_id_file: Some(channel_id_file.display().to_string()),
            state_file: Some(temp.path().join("threads.json").display().to_string()),
            ..AgentNotifyConfig::default()
        };
        let client = FakeSlackClient::new();
        let parent_payload = json!({
            "hook_event_name": "ThreadNameUpdated",
            "cwd": "/tmp/thread-project",
            "thread_name": "Plan質問をテスト",
            "session_id": "019df3f2-315b-7e23-8f91-cb8c05a68ea6"
        });
        let parent = codex_notification_from_payload(&parent_payload, None).expect("parent");
        send_notification_with_client(&config, &parent, true, &client).expect("send parent");

        let reply_payload = json!({
            "hook_event_name": "RequestUserInput",
            "cwd": "/tmp/thread-project",
            "session_id": "019df3f2-315b-7e23-8f91-cb8c05a68ea6",
            "tool_input": {"questions": [{"question": "Choose an option."}]}
        });
        let reply = codex_notification_from_payload(&reply_payload, None).expect("reply");
        send_notification_with_client(&config, &reply, true, &client).expect("send reply");

        let api_payloads = client.api_payloads.borrow();
        assert_eq!(api_payloads.len(), 2);
        assert!(api_payloads[0].get("thread_ts").is_none());
        assert_eq!(api_payloads[1]["thread_ts"], "111.000001");
        let state: ThreadState = serde_json::from_str(
            &fs::read_to_string(temp.path().join("threads.json")).expect("state"),
        )
        .expect("parse state");
        assert_eq!(
            state.threads["019df3f2-315b-7e23-8f91-cb8c05a68ea6"].thread_ts,
            "111.000001"
        );
    }

    #[test]
    fn webhook_fallback_skips_parent_but_allows_reply() {
        let temp = tempdir().expect("tempdir");
        let webhook_file = temp.path().join("webhook");
        fs::write(&webhook_file, "https://example.invalid/slack\n").expect("webhook");
        let config = AgentNotifyConfig {
            bot_token_file: Some(temp.path().join("missing-token").display().to_string()),
            channel_id_file: Some(temp.path().join("missing-channel").display().to_string()),
            webhook_file: Some(webhook_file.display().to_string()),
            ..AgentNotifyConfig::default()
        };
        let client = FakeSlackClient::new();
        let parent_payload = json!({
            "hook_event_name": "ThreadNameUpdated",
            "cwd": "/tmp/thread-project",
            "thread_name": "Title",
            "session_id": "019df3f2-315b-7e23-8f91-cb8c05a68ea6"
        });
        let parent = codex_notification_from_payload(&parent_payload, None).expect("parent");
        assert!(
            send_notification_with_client(&config, &parent, false, &client)
                .expect("parent fallback")
                .eq(&false)
        );
        assert!(client.webhook_payloads.borrow().is_empty());

        let reply_payload = json!({
            "hook_event_name": "Stop",
            "cwd": "/tmp/thread-project",
            "last_assistant_message": "Done."
        });
        let reply = codex_notification_from_payload(&reply_payload, None).expect("reply");
        assert!(send_notification_with_client(&config, &reply, true, &client).expect("reply"));
        assert_eq!(client.webhook_payloads.borrow().len(), 1);
    }
}

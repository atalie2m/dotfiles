use crate::commands::{AgentNotifyArgs, AgentNotifyCommand};
use dotfiles_core::agent_notifications::{
    run_codex_notification, run_test_notification, AgentNotifyConfig, CodexNotifyOptions,
    TestNotifyOptions,
};

pub(crate) fn command_agent_notify(args: &AgentNotifyArgs) -> Result<(), String> {
    match &args.command {
        AgentNotifyCommand::Codex(args) => run_codex_notification(
            AgentNotifyConfig {
                dry_run: args.dry_run,
                bot_token_file: args.bot_token_file.clone(),
                channel_id_file: args.channel_id_file.clone(),
                webhook_file: args.webhook_file.clone(),
                state_file: args.state_file.clone(),
                dedupe_state_file: args
                    .dedupe_state_file
                    .clone()
                    .or_else(|| args.question_state_file.clone()),
                error_log_file: args.error_log_file.clone(),
                slack_api_url: args.slack_api_url.clone(),
                slack_update_api_url: args.slack_update_api_url.clone(),
            },
            CodexNotifyOptions {
                payload_args: args.payload_args.clone(),
                event_name: args.event_name.clone(),
                spawn_watcher: args.spawn_watcher || args.spawn_question_watcher,
                watch_transcript: args.watch_transcript.clone(),
                watch_from_start: args.watch_from_start,
                watch_timeout_seconds: args.watch_timeout_seconds,
                session_id: args.session_id.clone(),
                cwd: args.cwd.clone(),
            },
        ),
        AgentNotifyCommand::Test(args) => run_test_notification(
            AgentNotifyConfig {
                dry_run: args.dry_run,
                bot_token_file: args.bot_token_file.clone(),
                channel_id_file: args.channel_id_file.clone(),
                webhook_file: args.webhook_file.clone(),
                state_file: args.state_file.clone(),
                dedupe_state_file: args.dedupe_state_file.clone(),
                error_log_file: args.error_log_file.clone(),
                slack_api_url: args.slack_api_url.clone(),
                slack_update_api_url: args.slack_update_api_url.clone(),
            },
            TestNotifyOptions {
                cwd: args.cwd.clone(),
            },
        ),
        AgentNotifyCommand::UpdateRuntime(args) => {
            super::update::update_dotfiles_user_profile(!args.no_install)
        }
    }
}

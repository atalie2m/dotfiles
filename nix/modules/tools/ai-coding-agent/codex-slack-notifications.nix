{ dotmod, config, lib, pkgs, ... }:

# Codex lifecycle notifications to Slack.

let
  dotfilesCli = pkgs.callPackage ../../../pkgs/dotfiles-cli { };
in
(dotmod.mkModule { inherit config; }) {
  path = "tools.aiCodingAgent.codex.slackNotifications";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  myconfigOnEnable = { ... }: {
    tools.aiCodingAgent.enable = lib.mkDefault true;
    tools.aiCodingAgent.codex.enable = lib.mkDefault true;
  };

  homeOnEnable = { ... }: {
    home.packages = [ dotfilesCli ];
  };
}

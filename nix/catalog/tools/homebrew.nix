{
  # System
  aerospace = {
    group = "system";
    taps = [ "nikitabobko/tap" ];
    casks = [ "nikitabobko/tap/aerospace" ];
  };
  keyclu = {
    group = "system";
    casks = [ "keyclu" ];
  };
  latestApp = {
    group = "system";
    casks = [ "latest" ];
  };
  xcodesApp = {
    group = "system";
    casks = [ "xcodes-app" ];
  };

  # Terminals
  alacritty = {
    group = "terminal";
    casks = [ "alacritty" ];
  };
  ghostty = {
    group = "terminal";
    casks = [ "ghostty" ];
  };

  # AI coding agents
  claudeCode = {
    group = "aiCodingAgent";
    casks = [ "claude-code" ];
  };
  codex = {
    group = "aiCodingAgent";
    casks = [ "codex" ];
  };
  geminiCli = {
    group = "aiCodingAgent";
    brews = [ "gemini-cli" ];
  };
  githubCopilotCli = {
    group = "aiCodingAgent";
    casks = [ "copilot-cli" ];
  };
  opencode = {
    group = "aiCodingAgent";
    taps = [ "anomalyco/tap" ];
    brews = [ "anomalyco/tap/opencode" ];
  };
}

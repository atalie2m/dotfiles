{
  "system.aerospace" = {
    group = "system";
    tool = "aerospace";
    optionPath = [ "myconfig" "tools" "system" "aerospace" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    taps = [ "nikitabobko/tap" ];
    casks = [ "nikitabobko/tap/aerospace" ];
  };
  "system.keyclu" = {
    group = "system";
    tool = "keyclu";
    optionPath = [ "myconfig" "tools" "system" "keyclu" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "keyclu" ];
  };
  "system.latestApp" = {
    group = "system";
    tool = "latestApp";
    optionPath = [ "myconfig" "tools" "system" "latestApp" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "latest" ];
  };
  "system.xcodesApp" = {
    group = "system";
    tool = "xcodesApp";
    optionPath = [ "myconfig" "tools" "system" "xcodesApp" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "xcodes-app" ];
  };

  "terminal.alacritty" = {
    group = "terminal";
    tool = "alacritty";
    optionPath = [ "myconfig" "tools" "terminal" "alacritty" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "alacritty" ];
  };
  "terminal.ghostty" = {
    group = "terminal";
    tool = "ghostty";
    optionPath = [ "myconfig" "tools" "terminal" "ghostty" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "ghostty" ];
  };
  "terminal.rio" = {
    group = "terminal";
    tool = "rio";
    optionPath = [ "myconfig" "tools" "terminal" "rio" "enable" ];
    mode = "dedicated";
    backend = "homebrewNative";
    casks = [ "rio" ];
  };
  "terminal.wezterm" = {
    group = "terminal";
    tool = "wezterm";
    optionPath = [ "myconfig" "tools" "terminal" "wezterm" "enable" ];
    mode = "dedicated";
    backend = "homebrewNative";
    casks = [ "wezterm" ];
  };

  "aiCodingAgent.codex" = {
    group = "aiCodingAgent";
    tool = "codex";
    optionPath = [ "myconfig" "tools" "aiCodingAgent" "codex" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "codex" ];
  };
  "aiCodingAgent.geminiCli" = {
    group = "aiCodingAgent";
    tool = "geminiCli";
    optionPath = [ "myconfig" "tools" "aiCodingAgent" "geminiCli" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    brews = [ "gemini-cli" ];
  };
  "aiCodingAgent.githubCopilotCli" = {
    group = "aiCodingAgent";
    tool = "githubCopilotCli";
    optionPath = [ "myconfig" "tools" "aiCodingAgent" "githubCopilotCli" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    casks = [ "copilot-cli" ];
  };
  "aiCodingAgent.opencode" = {
    group = "aiCodingAgent";
    tool = "opencode";
    optionPath = [ "myconfig" "tools" "aiCodingAgent" "opencode" "enable" ];
    mode = "catalog";
    backend = "homebrewNative";
    taps = [ "anomalyco/tap" ];
    brews = [ "anomalyco/tap/opencode" ];
  };

  "editor.emacs" = {
    group = "editor";
    tool = "emacs";
    optionPath = [ "myconfig" "tools" "editor" "emacs" "enable" ];
    mode = "dedicated";
    backend = "homebrewNative";
    taps = [ "d12frosted/emacs-plus" ];
    casks = [ "emacs-plus-app" ];
  };
  "system.karabiner" = {
    group = "system";
    tool = "karabiner";
    optionPath = [ "myconfig" "tools" "system" "karabiner" "enable" ];
    mode = "dedicated";
    backend = "homebrewNative";
    casks = [ "karabiner-elements" ];
  };
}

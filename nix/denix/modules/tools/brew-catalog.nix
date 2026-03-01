{ delib, lib, dotlib, ... }:

let
  mkBrewToolModule = toolName: spec:
    delib.module {
      name = "tools.${spec.group}.${toolName}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };

      myconfig = {
        always = dotlib.mkEnableDefault "tools.${spec.group}.${toolName}.enable";
        ifEnabled = { myconfig, ... }:
          dotlib.ifDarwin myconfig (dotlib.requireHomebrew {
            taps = spec.taps or [ ];
            brews = spec.brews or [ ];
            casks = spec.casks or [ ];
            masApps = spec.masApps or { };
          });
      };
    };

  brewCatalog = {
    # System
    aerospace = {
      group = "system";
      taps = [ "nikitabobko/tap" ];
      casks = [ "nikitabobko/tap/aerospace" ];
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
  };
in
{
  imports = lib.mapAttrsToList mkBrewToolModule brewCatalog;
}

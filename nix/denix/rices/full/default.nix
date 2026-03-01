{ delib, ... }:

# Full rice: Complete development and productivity environment
delib.rice {
  name = "full";
  inherits = [ "minimum" ];

  myconfig = {
    # Override system overview for full profile
    system.overview = {
      enable = true;
      profile = "full";
      features = {
        developmentTools = true;
        productivitySuite = true;
        guiApplications = true;
        cloudSync = false;
      };
    };

    tools.aiCodingAgent.enable = true;
    tools.dev.enable = true;
    tools.editor.emacs.enable = true;
    tools.editor.neovim.enable = true;
    tools.editor.vscode.enable = true;
    tools.shell.enable = true;
    tools.shell.defaultShell = "zsh";
    tools.system.karabiner.enable = true;
    tools.system.aerospace.enable = true;
    tools.system.nixHomebrew.enable = true;
    tools.system.homebrewNative.enable = true;
    tools.system.homebrewNative.casks = [
      "keyclu"
      "latest"
      "alacritty"
      "ghostty"
      "wezterm"
      "xcodes-app"
    ];

  };
}

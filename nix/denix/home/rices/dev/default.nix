{ delib, ... }:

# Home dev rice mirrors host defaults, but is inheritance-only to keep
# homeConfigurations at one entry per host.
delib.rice {
  name = "dev";
  inherits = [ "base" ];
  inheritanceOnly = true;

  myconfig = {
    tools.aiCodingAgent.enable = true;
    tools.dev.enable = true;
    tools.editor.emacs.enable = true;
    tools.editor.neovim.enable = true;
    tools.editor.vscode.enable = true;
    tools.shell.defaultShell = "zsh";
    tools.system.karabiner.enable = true;
    tools.system.aerospace.enable = true;
    tools.terminal.rio.enable = true;
    tools.terminal.terminalApp = {
      enable = true;
      defaultProfile = "Atalie Standard";
      startupProfile = "Atalie Standard";
    };

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

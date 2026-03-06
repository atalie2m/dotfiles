{ delib, ... }:

# Dev rice: editor and workstation stack.
delib.rice {
  name = "dev";
  inherits = [ "base" ];

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

{ delib, inputs, ... }:

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
    tools.terminal.terminalApp = {
      enable = true;
      profiles = {
        "Atalie Standard" = "${inputs.self}/apps/terminal/Atalie-Standard.terminal";
        "Atalie Dark" = "${inputs.self}/apps/terminal/Atalie-Dark.terminal";
        "Atalie Glass" = "${inputs.self}/apps/terminal/Atalie-Glass.terminal";
        "Atalie Glass Dark" = "${inputs.self}/apps/terminal/Atalie-Glass-Dark.terminal";
        "Atalie Glass Light" = "${inputs.self}/apps/terminal/Atalie-Glass-Light.terminal";
      };
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

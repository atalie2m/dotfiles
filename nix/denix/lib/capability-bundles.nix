{
  base = {
    system.nix.enable = true;
    tools.core.enable = true;
    tools.shell.enable = true;
    tools.dev.git.enable = true;
    tools.security.enable = true;
  };

  darwin = {
    tools.system.nixHomebrew.enable = true;
    tools.system.homebrewNative.enable = true;
    tools.system.hostnames.enable = true;
    tools.system.fonts.enable = true;
    tools.system.macosUi.enable = true;
  };

  dev = {
    tools.aiCodingAgent.enable = true;
    tools.dev.enable = true;
    tools.editor.emacs.enable = true;
    tools.editor.neovim.enable = true;
    tools.editor.vscode.enable = true;
    tools.dev.git.delta.enable = true;
    tools.shell.defaultShell = "zsh";
    tools.shell.atuin.enable = true;
    tools.shell.direnv.enable = true;
    tools.shell.fzf.enable = true;
    tools.shell.fzfTab.enable = true;
    tools.shell.zoxide.enable = true;
    tools.system.karabiner.enable = true;
    tools.system.aerospace.enable = true;
    tools.system.keyclu.enable = true;
    tools.system.latestApp.enable = true;
    tools.system.xcodesApp.enable = true;
    tools.terminal.alacritty.enable = true;
    tools.terminal.ghostty.enable = true;
    tools.terminal.wezterm.enable = true;
    tools.terminal.rio.enable = true;
  };

  partialOverride = {
    tools.editor.vscode.sync.enable = false;
  };

  ultraOverride = {
    tools.dev.ansible.enable = false;
    tools.dev.go.enable = false;
    tools.dev.nodejs.enable = false;
    tools.dev.opentofu.enable = false;
    tools.dev.terraform.enable = false;
    tools.dev.gitAbsorb.enable = true;
    tools.dev.gnugrep.enable = true;
    tools.dev.gnused.enable = true;
    tools.dev.git.lfs.enable = true;
  };

  proOverride = {
    tools.editor.vscode.sync.enable = false;
    tools.dev.ansible.enable = false;
    tools.dev.go.enable = false;
    tools.dev.nodejs.enable = false;
    tools.dev.opentofu.enable = false;
    tools.dev.terraform.enable = false;
    tools.dev.gitAbsorb.enable = true;
    tools.dev.gnugrep.enable = true;
    tools.dev.gnused.enable = true;
    tools.dev.git.lfs.enable = true;
  };
}

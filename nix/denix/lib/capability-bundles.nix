{
  base = {
    system.nix.enable = true;
    tools.system.keyboard.enable = true;
    tools.core.enable = true;
    tools.core.bat.enable = true;
    tools.core.coreutils.enable = true;
    tools.core.curl.enable = true;
    tools.core.eza.enable = true;
    tools.core.fd.enable = true;
    tools.core.htop.enable = true;
    tools.core.httpie.enable = true;
    tools.core.jq.enable = true;
    tools.core.just.enable = true;
    tools.core.nmap.enable = true;
    tools.core.nkf.enable = true;
    tools.core.python3.enable = true;
    tools.core.ripgrep.enable = true;
    tools.core.tree.enable = true;
    tools.core.unzip.enable = true;
    tools.core.watchexec.enable = true;
    tools.core.wget.enable = true;
    tools.core.yq.enable = true;
    tools.core.zip.enable = true;

    tools.shell.enable = true;
    tools.shell.zsh.enable = true;
    tools.shell.bash.enable = true;
    tools.shell.pure.enable = true;
    tools.shell.sync.enable = true;

    tools.dev.git.enable = true;
    tools.dev.git.lfs.enable = true;

    tools.security.enable = true;
    tools.security.gpg.enable = true;
    tools.security.sops.enable = true;
  };

  darwin = {
    tools.system.enable = true;
    tools.system.brewNix.enable = false;
    tools.system.brewNix.appLinks.enable = false;
    tools.system.brewNix.autoDock.enable = false;
    tools.system.nixHomebrew.enable = true;
    tools.system.nixHomebrew.autoMigrate = false;
    tools.system.homebrewNative.enable = true;
    tools.system.hostnames.enable = true;
    tools.system.fonts.enable = true;
    tools.system.macosUi.enable = true;
    tools.system.macAppUtil.systemService.enable = false;
    tools.system.macAppUtil.homeTrampolines.syncDock = false;
    # Show hidden apps as translucent Dock icons.
    tools.system.macosUi.dock.showHiddenApplications = true;
    # Keep Finder from writing .DS_Store on removable/network volumes.
    tools.system.macosUi.finder.writeDSStoreOnNetworkVolumes = false;
    tools.system.macosUi.finder.writeDSStoreOnUSBVolumes = false;
  };

  dev = {
    tools.aiCodingAgent.enable = true;

    tools.dev.enable = true;
    tools.dev.ansible.enable = true;
    tools.dev.awscli2.enable = true;
    tools.dev.gh.enable = true;
    tools.dev.go.enable = true;
    tools.dev.gitAbsorb.enable = true;
    tools.dev.gnugrep.enable = true;
    tools.dev.gnused.enable = true;
    tools.dev.mercurial.enable = true;
    tools.dev.nodejs.enable = true;
    tools.dev.opentofu.enable = true;
    tools.dev.terraform.enable = true;
    tools.dev.git.delta.enable = true;

    tools.editor.enable = true;
    tools.editor.emacs.enable = true;
    tools.editor.neovim.enable = true;

    tools.shell.atuin.enable = true;
    tools.shell.direnv.enable = true;
    tools.shell.fzf.enable = true;
    tools.shell.fzfTab.enable = true;
    tools.shell.zoxide.enable = true;
    tools.shell.defaultShell = "zsh";

    tools.system.aerospace.enable = true;
    tools.system.karabiner.enable = true;
    tools.system.keyclu.enable = true;
    tools.system.latestApp.enable = true;
    tools.system.xcodesApp.enable = true;

    tools.terminal.enable = true;
    tools.terminal.alacritty.enable = true;
    tools.terminal.ghostty.enable = true;
    tools.terminal.wezterm.enable = true;
    tools.terminal.rio.enable = true;
  };

  partialOverride = {
    tools.aiCodingAgent.claudeCode.enable = false;
    tools.aiCodingAgent.codex.enable = true;
    tools.aiCodingAgent.geminiCli.enable = false;
    tools.aiCodingAgent.githubCopilotCli.enable = false;
    tools.aiCodingAgent.opencode.enable = false;
    tools.editor.vscode.enable = false;
    tools.editor.vscode.sync.enable = false;
  };

  ultraOverride = {
    tools.aiCodingAgent.claudeCode.enable = true;
    tools.aiCodingAgent.codex.enable = true;
    tools.aiCodingAgent.geminiCli.enable = true;
    tools.aiCodingAgent.githubCopilotCli.enable = true;
    tools.aiCodingAgent.opencode.enable = true;
    tools.editor.vscode.enable = true;
    tools.editor.vscode.sync.enable = false;
  };

  proOverride = {
    tools.aiCodingAgent.claudeCode.enable = true;
    tools.aiCodingAgent.codex.enable = true;
    tools.aiCodingAgent.geminiCli.enable = true;
    tools.aiCodingAgent.githubCopilotCli.enable = true;
    tools.aiCodingAgent.opencode.enable = true;
    tools.editor.vscode.enable = false;
    tools.editor.vscode.sync.enable = false;
  };
}

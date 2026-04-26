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
    tools.shell.zsh.profile = "stable";
    tools.shell.bash.enable = true;
    tools.shell.pure.enable = true;
    tools.shell.sync.enable = true;
    tools.shell.atuin.enable = true;
    tools.shell.direnv.enable = true;
    tools.shell.fzf.enable = true;
    tools.shell.fzfTab.enable = true;
    tools.shell.zoxide.enable = true;

    tools.shellUx.enable = true;
    tools.shellUx.fzf.enable = true;
    tools.shellUx.television.enable = true;
    tools.shellUx.watchexec.enable = true;
    tools.shellUx.hyperfine.enable = true;
    tools.shellUx.chezmoi.enable = true;
    tools.shellUx.topgrade.enable = true;

    tools.filesNavigation.enable = true;
    tools.filesNavigation.eza.enable = true;
    tools.filesNavigation.fd.enable = true;
    tools.filesNavigation.zoxide.enable = true;
    tools.filesNavigation.yazi.enable = true;
    tools.filesNavigation.dust.enable = true;
    tools.filesNavigation.duf.enable = true;

    tools.viewersPreview.enable = true;
    tools.viewersPreview.bat.enable = true;
    tools.viewersPreview.delta.enable = true;

    tools.searchText.enable = true;
    tools.searchText.ripgrep.enable = true;
    tools.searchText.fd.enable = true;
    tools.searchText.fzf.enable = true;

    tools.gitPersonal.enable = true;
    tools.gitPersonal.delta.enable = true;
    tools.gitPersonal.lazygit.enable = true;
    tools.gitPersonal.gh.enable = true;
    tools.gitPersonal.ghDash.enable = true;
    tools.gitPersonal.jujutsu.enable = true;

    tools.nixOperator.enable = true;
    tools.nixOperator.nh.enable = true;
    tools.nixOperator.nom.enable = true;
    tools.nixOperator.nixIndex.enable = true;
    tools.nixOperator.nixSearchTv.enable = true;
    tools.nixOperator.direnv.enable = true;
    tools.nixOperator.nixDirenv.enable = true;
    tools.nixOperator.nixYourShell.enable = true;
    tools.nixOperator.nixd.enable = true;
    tools.nixOperator.nil.enable = true;
    tools.nixOperator.topgrade.enable = true;
    tools.nixOperator.alejandra.enable = true;

    tools.observability.enable = true;
    tools.observability.btop.enable = true;
    tools.observability.procs.enable = true;

    tools.network.enable = true;
    tools.network.trippy.enable = true;
    tools.network.doggo.enable = true;
    tools.network.xh.enable = true;

    tools.passwordSecrets.enable = true;
    tools.passwordSecrets.bw.enable = true;
    tools.passwordSecrets.op.enable = true;

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
    tools.dev.gitAbsorb.enable = true;
    tools.dev.gnugrep.enable = true;
    tools.dev.gnused.enable = true;
    tools.dev.mercurial.enable = true;
    tools.dev.git.delta.enable = true;

    tools.editor.enable = true;
    tools.editor.emacs.enable = true;
    tools.editor.emacs.sync.enable = true;
    tools.editor.emacs.bootstrap.enable = true;
    tools.editor.neovim.enable = true;

    tools.shell.atuin.enable = true;
    tools.shell.direnv.enable = true;
    tools.shell.fzf.enable = true;
    tools.shell.fzfTab.enable = true;
    tools.shell.zoxide.enable = true;
    tools.shell.defaultShell = "zsh";

    tools.shellUx.skim.enable = true;
    tools.shellUx.peco.enable = true;
    tools.shellUx.navi.enable = true;
    tools.shellUx.gum.enable = true;
    tools.shellUx.comma.enable = true;
    tools.shellUx.payRespects.enable = true;
    tools.shellUx.fend.enable = true;
    tools.shellUx.qalc.enable = true;
    tools.shellUx.vivid.enable = true;
    tools.shellUx.entr.enable = true;
    tools.shellUx.gping.enable = true;

    tools.filesNavigation.broot.enable = true;
    tools.filesNavigation.superfile.enable = true;
    tools.filesNavigation.ncdu.enable = true;
    tools.filesNavigation.dysk.enable = true;
    tools.filesNavigation.croc.enable = true;
    tools.filesNavigation.trashCli.enable = true;
    tools.filesNavigation.rsync.enable = true;
    tools.filesNavigation.rclone.enable = true;
    tools.filesNavigation.ouch.enable = true;

    tools.viewersPreview.batExtras.enable = true;
    tools.viewersPreview.glow.enable = true;
    tools.viewersPreview.tealdeer.enable = true;
    tools.viewersPreview.chafa.enable = true;
    tools.viewersPreview.hexyl.enable = true;
    tools.viewersPreview.less.enable = true;
    tools.viewersPreview.mdcat.enable = true;
    tools.viewersPreview.fq.enable = true;
    tools.viewersPreview.fx.enable = true;

    tools.searchText.ripgrepAll.enable = true;
    tools.searchText.grex.enable = true;
    tools.searchText.sd.enable = true;
    tools.searchText.difftastic.enable = true;
    tools.searchText.diffSoFancy.enable = true;
    tools.searchText.delta.enable = true;

    tools.gitPersonal.gitui.enable = true;
    tools.gitPersonal.gitAbsorb.enable = true;
    tools.gitPersonal.sapling.enable = true;
    tools.gitPersonal.gitBranchless.enable = true;
    tools.gitPersonal.gitoxide.enable = true;
    tools.gitPersonal.mergiraf.enable = true;
    tools.gitPersonal.gitFilterRepo.enable = true;
    tools.gitPersonal.onefetch.enable = true;
    tools.gitPersonal.tokei.enable = true;

    tools.nixOperator.manix.enable = true;
    tools.nixOperator.nixInspect.enable = true;
    tools.nixOperator.nixTree.enable = true;
    tools.nixOperator.nvd.enable = true;
    tools.nixOperator.nixInit.enable = true;
    tools.nixOperator.nurl.enable = true;
    tools.nixOperator.nixUpdate.enable = true;

    tools.observability.bottom.enable = true;
    tools.observability.bandwhich.enable = true;
    tools.observability.glances.enable = true;
    tools.observability.iftop.enable = true;
    tools.observability.sniffnet.enable = true;
    tools.observability.macmon.enable = true;
    tools.observability.macpm.enable = true;
    tools.observability.fastfetch.enable = true;
    tools.observability.htop.enable = true;
    tools.observability.samply.enable = true;
    tools.observability.pySpy.enable = true;
    tools.observability.goss.enable = true;
    tools.observability.lnav.enable = true;

    tools.network.mtr.enable = true;
    tools.network.dig.enable = true;
    tools.network.curl.enable = true;
    tools.network.wget.enable = true;
    tools.network.gping.enable = true;
    tools.network.mosh.enable = true;
    tools.network.keychain.enable = true;
    tools.network.teleport.enable = true;
    tools.network.tsh.enable = true;
    tools.network.termshark.enable = true;
    tools.network.rustscan.enable = true;
    tools.network.nmap.enable = true;
    tools.network.bandwhich.enable = true;
    tools.network.sniffnet.enable = true;
    tools.network.websocat.enable = true;
    tools.network.grpcurl.enable = true;

    tools.httpApiPersonal.enable = true;
    tools.httpApiPersonal.xh.enable = true;
    tools.httpApiPersonal.curl.enable = true;
    tools.httpApiPersonal.httpie.enable = true;
    tools.httpApiPersonal.atac.enable = true;
    tools.httpApiPersonal.jq.enable = true;
    tools.httpApiPersonal.yq.enable = true;
    tools.httpApiPersonal.fx.enable = true;

    tools.downloadArchive.enable = true;
    tools.downloadArchive.ouch.enable = true;
    tools.downloadArchive.tar.enable = true;
    tools.downloadArchive.gzip.enable = true;
    tools.downloadArchive.pigz.enable = true;
    tools.downloadArchive.zstd.enable = true;
    tools.downloadArchive.unzip.enable = true;
    tools.downloadArchive.p7zip.enable = true;
    tools.downloadArchive.aria2.enable = true;
    tools.downloadArchive.ytDlp.enable = true;
    tools.downloadArchive.ffmpeg.enable = true;
    tools.downloadArchive.rclone.enable = true;
    tools.downloadArchive.rsync.enable = true;

    tools.tuiWorkspace.enable = true;
    tools.tuiWorkspace.zellij.enable = true;
    tools.tuiWorkspace.tmux.enable = true;
    tools.tuiWorkspace.sesh.enable = true;
    tools.tuiWorkspace.k9s.enable = true;
    tools.tuiWorkspace.lazydocker.enable = true;
    tools.tuiWorkspace.stern.enable = true;
    tools.tuiWorkspace.lnav.enable = true;
    tools.tuiWorkspace.toast.enable = true;
    tools.tuiWorkspace.gobang.enable = true;
    tools.tuiWorkspace.harlequin.enable = true;
    tools.tuiWorkspace.pgActivity.enable = true;
    tools.tuiWorkspace.atuin.enable = true;

    tools.dataPersonal.enable = true;
    tools.dataPersonal.jq.enable = true;
    tools.dataPersonal.yq.enable = true;
    tools.dataPersonal.fx.enable = true;
    tools.dataPersonal.jc.enable = true;
    tools.dataPersonal.miller.enable = true;
    tools.dataPersonal.visidata.enable = true;
    tools.dataPersonal.dasel.enable = true;
    tools.dataPersonal.qsv.enable = true;
    tools.dataPersonal.xan.enable = true;
    tools.dataPersonal.csvlens.enable = true;
    tools.dataPersonal.sq.enable = true;
    tools.dataPersonal.duckdb.enable = true;
    tools.dataPersonal.fq.enable = true;
    tools.dataPersonal.usql.enable = true;
    tools.dataPersonal.harlequin.enable = true;
    tools.dataPersonal.pgActivity.enable = true;

    tools.containerK8sPersonal.enable = true;
    tools.containerK8sPersonal.docker.enable = true;
    tools.containerK8sPersonal.podman.enable = true;
    tools.containerK8sPersonal.lazydocker.enable = true;
    tools.containerK8sPersonal.kubectl.enable = true;
    tools.containerK8sPersonal.k9s.enable = true;
    tools.containerK8sPersonal.stern.enable = true;
    tools.containerK8sPersonal.kubie.enable = true;
    tools.containerK8sPersonal.kubecolor.enable = true;

    tools.securityPersonal.enable = true;
    tools.securityPersonal.rustscan.enable = true;
    tools.securityPersonal.nmap.enable = true;
    tools.securityPersonal.sshAudit.enable = true;
    tools.securityPersonal.minisign.enable = true;
    tools.securityPersonal.sops.enable = true;
    tools.securityPersonal.age.enable = true;
    tools.securityPersonal.agePluginYubikey.enable = true;
    tools.securityPersonal.flawz.enable = true;
    tools.securityPersonal.gitleaks.enable = true;
    tools.securityPersonal.trufflehog.enable = true;
    tools.securityPersonal.noseyparker.enable = true;

    tools.passwordSecrets.rbw.enable = true;
    tools.passwordSecrets.sops.enable = true;
    tools.passwordSecrets.age.enable = true;
    tools.passwordSecrets.agePluginYubikey.enable = true;
    tools.passwordSecrets.sshToAge.enable = true;
    tools.passwordSecrets.keychain.enable = true;

    tools.aiLlm.enable = true;
    tools.aiLlm.aider.enable = true;
    tools.aiLlm.llm.enable = true;
    tools.aiLlm.ollama.enable = true;
    tools.aiLlm.llamaCpp.enable = true;
    tools.aiLlm.goose.enable = true;
    tools.aiLlm.crush.enable = true;
    tools.aiLlm.huggingfaceHub.enable = true;

    tools.modelHfPersonal.enable = true;
    tools.modelHfPersonal.gitLfs.enable = true;
    tools.modelHfPersonal.gitXet.enable = true;
    tools.modelHfPersonal.huggingfaceHub.enable = true;
    tools.modelHfPersonal.rclone.enable = true;
    tools.modelHfPersonal.aria2.enable = true;
    tools.modelHfPersonal.croc.enable = true;

    tools.backupRecovery.enable = true;
    tools.backupRecovery.restic.enable = true;
    tools.backupRecovery.borgbackup.enable = true;
    tools.backupRecovery.kopia.enable = true;
    tools.backupRecovery.rclone.enable = true;
    tools.backupRecovery.rsync.enable = true;

    tools.terminalVisual.enable = true;
    tools.terminalVisual.ankaCoder.enable = true;
    tools.terminalVisual.kitty.enable = true;
    tools.terminalVisual.vivid.enable = true;
    tools.terminalVisual.chafa.enable = true;
    tools.terminalVisual.vhs.enable = true;

    tools.system.aerospace.enable = true;
    tools.system.karabiner.enable = true;
    tools.system.keyclu.enable = true;
    tools.system.latestApp.enable = true;
    tools.system.xcodesApp.enable = true;
    tools.system.swiftgen.enable = true;
    tools.system.sourcery.enable = true;
    tools.system.periphery.enable = true;
    tools.system.carthage.enable = true;

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

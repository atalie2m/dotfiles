{ lib }:

let
  merge = builtins.foldl' lib.recursiveUpdate { };
  sharedBundles = import ../shared/bundles.nix;
in
rec {
  minimal = {
    system.nix.enable = true;

    tools.core.enable = true;
    tools.core.bat.enable = true;
    tools.core.coreutils.enable = true;
    tools.core.curl.enable = true;
    tools.core.eza.enable = true;
    tools.core.fd.enable = true;
    tools.core.htop.enable = true;
    tools.core.jq.enable = true;
    tools.core.just.enable = true;
    tools.core.ripgrep.enable = true;
    tools.core.tree.enable = true;
    tools.core.unzip.enable = true;
    tools.core.wget.enable = true;
    tools.core.yq.enable = true;
    tools.core.zip.enable = true;

    tools.dev.git.enable = true;

    tools.shell.enable = true;
    tools.shell.bash.enable = true;
    tools.shell.fzf.enable = true;
    tools.shell.zoxide.enable = true;

    tools.filesNavigation.enable = true;
    tools.filesNavigation.eza.enable = true;
    tools.filesNavigation.fd.enable = true;
    tools.filesNavigation.zoxide.enable = true;

    tools.searchText.enable = true;
    tools.searchText.fd.enable = true;
    tools.searchText.fzf.enable = true;
    tools.searchText.ripgrep.enable = true;

    tools.nixOperator.enable = true;
    tools.nixOperator.deadnix.enable = true;
    tools.nixOperator.nh.enable = true;
    tools.nixOperator.nil.enable = true;
    tools.nixOperator.nixDiff.enable = true;
    tools.nixOperator.nom.enable = true;
    tools.nixOperator.statix.enable = true;
  };

  workbench = merge [
    minimal
    sharedBundles.portableWorkbench
    {
      tools.dev.actionlint.enable = true;
      tools.dev.gh.enable = true;
      tools.dev.git.delta.enable = true;
      tools.dev.git.lfs.enable = true;
      tools.dev.shellcheck.enable = true;
      tools.dev.shfmt.enable = true;
      tools.dev.taplo.enable = true;
      tools.dev.typos.enable = true;
      tools.dev.yamllint.enable = true;

      tools.editor.enable = true;
      tools.editor.neovim.enable = true;
      tools.editor.neovim.sync.enable = false;

      tools.gitPersonal.enable = true;
      tools.gitPersonal.delta.enable = true;
      tools.gitPersonal.gh.enable = true;
      tools.gitPersonal.gitSizer.enable = true;
      tools.gitPersonal.lazygit.enable = true;
      tools.gitPersonal.onefetch.enable = true;
      tools.gitPersonal.tokei.enable = true;

      tools.network.enable = true;
      tools.network.curl.enable = true;
      tools.network.dig.enable = true;
      tools.network.mosh.enable = true;
      tools.network.mtr.enable = true;
      tools.network.wget.enable = true;

      tools.nixOperator.alejandra.enable = true;
      tools.nixOperator.direnv.enable = true;
      tools.nixOperator.nixDirenv.enable = true;
      tools.nixOperator.nixTree.enable = true;
      tools.nixOperator.nvd.enable = true;

      tools.observability.enable = true;
      tools.observability.btop.enable = true;
      tools.observability.fastfetch.enable = true;
      tools.observability.htop.enable = true;
      tools.observability.lnav.enable = true;
      tools.observability.procs.enable = true;

      tools.searchText.astGrep.enable = true;
      tools.searchText.difftastic.enable = true;
      tools.searchText.sad.enable = true;
      tools.searchText.sd.enable = true;

      tools.security.enable = true;
      tools.security.sops.enable = true;

      tools.securityPersonal.enable = true;
      tools.securityPersonal.age.enable = true;
      tools.securityPersonal.gitleaks.enable = true;
      tools.securityPersonal.minisign.enable = true;
      tools.securityPersonal.nmap.enable = true;
      tools.securityPersonal.sops.enable = true;
      tools.securityPersonal.sshAudit.enable = true;

      tools.shell.defaultShell = "zsh";
      tools.shell.atuin.enable = true;
      tools.shell.bash.enable = true;
      tools.shell.direnv.enable = true;
      tools.shell.fzf.enable = true;
      tools.shell.fzfTab.enable = true;
      tools.shell.pure.enable = true;
      tools.shell.zoxide.enable = true;
      tools.shell.zsh.enable = true;
      tools.shell.zsh.profile = "stable";

      tools.shellUx.enable = true;
      tools.shellUx.fzf.enable = true;
      tools.shellUx.hyperfine.enable = true;
      tools.shellUx.watchexec.enable = true;

      tools.terminal.enable = true;
      tools.terminal.tmux.enable = true;

      tools.tuiWorkspace.enable = true;
      tools.tuiWorkspace.lnav.enable = true;
      tools.tuiWorkspace.tmux.enable = true;

      tools.viewersPreview.enable = true;
      tools.viewersPreview.bat.enable = true;
      tools.viewersPreview.delta.enable = true;
      tools.viewersPreview.glow.enable = true;
      tools.viewersPreview.less.enable = true;
    }
  ];
}

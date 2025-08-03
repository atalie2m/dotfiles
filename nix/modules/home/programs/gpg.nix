{ pkgs, ... }:

{
  programs.gpg = {
    enable = true;
  };

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    # Set TTY for proper GPG operation
    enableExtraSocket = true;
    pinentry.package = pkgs.pinentry_mac;

    defaultCacheTtl = 1800;        # 30 minutes
    defaultCacheTtlSsh = 1800;     # 30 minutes for SSH keys
    maxCacheTtl = 7200;            # 2 hours maximum

    enableBashIntegration = true;
    enableZshIntegration = true;
  };

  # GPG environment variables - ensure SSH uses GPG agent
  home.sessionVariables = {
    SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
    GPG_TTY = "$(tty)";
  };
}

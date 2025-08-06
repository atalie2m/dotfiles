{ delib, pkgs, ... }:

# GPG and GPG agent configuration
delib.module {
  name = "gpg";

  options.gpg = with delib.options; {
    enable = boolOption false;

    agent = {
      enableSshSupport = boolOption true;
      enableExtraSocket = boolOption true;
      defaultCacheTtl = intOption 1800;
      defaultCacheTtlSsh = intOption 1800;
      maxCacheTtl = intOption 7200;
    };
  };

  home.ifEnabled = { cfg, ... }: {
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      enableSshSupport = cfg.agent.enableSshSupport;
      enableExtraSocket = cfg.agent.enableExtraSocket;
      pinentry.package = pkgs.pinentry_mac;

      defaultCacheTtl = cfg.agent.defaultCacheTtl;
      defaultCacheTtlSsh = cfg.agent.defaultCacheTtlSsh;
      maxCacheTtl = cfg.agent.maxCacheTtl;

      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    home.sessionVariables = {
      SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
      GPG_TTY = "$(tty)";
    };
  };
}

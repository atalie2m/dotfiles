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
    # Ensure gpg CLI is available when the module is enabled
    home.packages = [ pkgs.gnupg ];

    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      inherit (cfg.agent) enableSshSupport enableExtraSocket defaultCacheTtl defaultCacheTtlSsh maxCacheTtl;
      pinentry.package = pkgs.pinentry_mac;

      enableBashIntegration = true;
      enableZshIntegration = true;
    };

    home.sessionVariables = {
      SSH_AUTH_SOCK = "$(gpgconf --list-dirs agent-ssh-socket)";
      GPG_TTY = "$(tty)";
    };
  };
}

{ dotmod, config, ... }:

# GPG and GPG agent configuration

(dotmod.mkModule { inherit config; }) {
  path = "tools.security.gpg";

  options = with dotmod; moduleOptions {
    enable = boolOption false;

    agent = {
      enableSshSupport = boolOption true;
      enableExtraSocket = boolOption true;
      defaultCacheTtl = intOption 1800;
      defaultCacheTtlSsh = intOption 1800;
      maxCacheTtl = intOption 7200;
    };
  };

  homeOnEnable = { cfg, ... }: {
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      inherit (cfg.agent) enableSshSupport enableExtraSocket defaultCacheTtl defaultCacheTtlSsh maxCacheTtl;

      enableBashIntegration = true;
      enableZshIntegration = true;
    };

  };

  darwinOnEnable = { ... }: {
    home-manager.sharedModules = [
      ({ pkgs, ... }: {
        services.gpg-agent.pinentry.package = pkgs.pinentry_mac;
      })
    ];
  };
}

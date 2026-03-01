{ delib, lib, ... }:

# GPG and GPG agent configuration
delib.module {
  name = "tools.security.gpg";

  options = with delib; moduleOptions {
    enable = boolOption false;

    agent = {
      enableSshSupport = boolOption true;
      enableExtraSocket = boolOption true;
      defaultCacheTtl = intOption 1800;
      defaultCacheTtlSsh = intOption 1800;
      maxCacheTtl = intOption 7200;
    };
  };

  myconfig = {
    always = { parent, ... }: {
      tools.security.gpg.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, ... }: {
    programs.gpg.enable = true;

    services.gpg-agent = {
      enable = true;
      inherit (cfg.agent) enableSshSupport enableExtraSocket defaultCacheTtl defaultCacheTtlSsh maxCacheTtl;

      enableBashIntegration = true;
      enableZshIntegration = true;
    };

  };

  darwin.ifEnabled = { ... }: {
    home-manager.sharedModules = [
      ({ pkgs, ... }: {
        services.gpg-agent.pinentry.package = pkgs.pinentry_mac;
      })
    ];
  };
}

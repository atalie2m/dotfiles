{ dotmod, config, inputs, lib, ... }:

# nix-homebrew: install Homebrew declaratively for nix-darwin

(dotmod.mkModule { inherit config; }) {
  path = "tools.system.nixHomebrew";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    autoMigrate = boolOption false;
  };

  darwinAlways = { ... }: {
    imports = [ inputs.nix-homebrew.darwinModules.nix-homebrew ];

    # Shell startup is owned by Home Manager below. Keep nix-homebrew from
    # generating `brew shellenv` calls, including in profiles where Homebrew is
    # currently disabled but may be enabled by a future host override.
    nix-homebrew = {
      enableBashIntegration = false;
      enableFishIntegration = false;
      enableZshIntegration = false;
    };
  };

  darwinOnEnable = { cfg, myconfig, ... }:
    let
      userName = myconfig.hostContext.user.username;
      hostSystem = myconfig.hostContext.system;
      enableRosetta = hostSystem == "aarch64-darwin";
      nativePrefixKey =
        if enableRosetta then
          config.nix-homebrew.defaultArm64Prefix
        else
          config.nix-homebrew.defaultIntelPrefix;
      nativePrefix = config.nix-homebrew.prefixes.${nativePrefixKey};
      homebrewPrefix = nativePrefix.prefix;
      homebrewRepository = "${nativePrefix.library}/.homebrew-is-managed-by-nix";
      homebrewSiteFunctions = "${homebrewPrefix}/share/zsh/site-functions";
      homebrewInfoPath = "${homebrewPrefix}/share/info";
    in
    {
      assertions = [
        {
          assertion = nativePrefix.enable;
          message = "tools.system.nixHomebrew requires the native Homebrew prefix for ${hostSystem}.";
        }
      ];

      nix-homebrew = {
        enable = true;
        user = userName;
        inherit enableRosetta;
        autoMigrate = cfg.autoMigrate;
        taps = {
          "d12frosted/homebrew-emacs-plus" = inputs.homebrew-emacs-plus;
        };
      };

      home-manager.sharedModules = [
        ({ ... }: {
          home = {
            # Keep reproducible Nix profile tools ahead of intentionally
            # latest-first Homebrew tools while still exposing Homebrew CLIs.
            sessionPath = lib.mkAfter [
              "${homebrewPrefix}/bin"
              "${homebrewPrefix}/sbin"
            ];

            sessionVariables = {
              HOMEBREW_PREFIX = homebrewPrefix;
              HOMEBREW_CELLAR = "${homebrewPrefix}/Cellar";
              HOMEBREW_REPOSITORY = homebrewRepository;
            };

            # Mirror the non-PATH parts of `brew shellenv` without running
            # Homebrew or macOS path_helper during shell startup.
            sessionVariablesExtra = lib.mkAfter ''
              if [ -n "''${ZSH_VERSION:-}" ]; then
                case ":''${FPATH:-}:" in
                  *":${homebrewSiteFunctions}:"*) ;;
                  *) export FPATH="${homebrewSiteFunctions}''${FPATH:+:$FPATH}" ;;
                esac
              fi

              [ -z "''${MANPATH-}" ] || export MANPATH=":''${MANPATH#:}"

              case ":''${INFOPATH:-}:" in
                *":${homebrewInfoPath}:"*) ;;
                *) export INFOPATH="${homebrewInfoPath}:''${INFOPATH:-}" ;;
              esac
            '';
          };
        })
      ];
    };
}

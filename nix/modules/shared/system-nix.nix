{ delib, lib, config, ... }:

let
  mkBinaryCaches = cfg:
    let
      factCaches = config.myconfig.hostContext.binaryCaches or { };
    in
    {
      extraSubstituters = lib.unique (cfg.binaryCaches.substituters ++ (factCaches.substituters or [ ]));
      extraTrustedPublicKeys = lib.unique (cfg.binaryCaches.trustedPublicKeys ++ (factCaches.trustedPublicKeys or [ ]));
    };

  mkCommonSettings = cfg:
    let
      caches = mkBinaryCaches cfg;
    in
    {
      experimental-features =
        (lib.optionals cfg.enableNixCommand [ "nix-command" ])
        ++ (lib.optionals cfg.enableFlakes [ "flakes" ])
        ++ cfg.extraExperimentalFeatures;

      accept-flake-config = cfg.acceptFlakeConfig;
    }
    // lib.optionalAttrs (caches.extraSubstituters != [ ]) {
      extra-substituters = caches.extraSubstituters;
    }
    // lib.optionalAttrs (caches.extraTrustedPublicKeys != [ ]) {
      extra-trusted-public-keys = caches.extraTrustedPublicKeys;
    };
in

# System-level Nix configuration
delib.module {
  name = "system.nix";

  options.system.nix = with delib.options; {
    enable = boolOption false;
    enableFlakes = boolOption true;
    enableNixCommand = boolOption true;
    acceptFlakeConfig = boolOption true;
    extraExperimentalFeatures = listOfOption str [ ];
    binaryCaches = {
      substituters = listOfOption str [ ];
      trustedPublicKeys = listOfOption str [ ];
    };
  };

  darwin.ifEnabled = { cfg, ... }:
    {
      nix = {
        settings = (mkCommonSettings cfg) // {
          trusted-users = [ "@admin" ];
        };

        # Enable garbage collection and optimization
        gc = {
          automatic = true;
          interval = { Weekday = 0; Hour = 2; Minute = 0; }; # Sunday at 2 AM
          options = "--delete-older-than 30d";
        };

        # Auto-optimize store (modern way)
        optimise.automatic = true;
      };
    };

  home.ifEnabled = { cfg, ... }: {
    # Home Manager Nix settings
    nix.settings = mkCommonSettings cfg;
  };
}

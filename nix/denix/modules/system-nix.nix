{ delib, lib, config, ... }:

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
    let
      factCaches = config.facts.binaryCaches or { };
      extraSubstituters = lib.unique (cfg.binaryCaches.substituters ++ (factCaches.substituters or [ ]));
      extraTrustedPublicKeys = lib.unique (cfg.binaryCaches.trustedPublicKeys ++ (factCaches.trustedPublicKeys or [ ]));
    in
    {
      nix = {
        settings = {
          # Enable experimental features
          experimental-features =
            (lib.optionals cfg.enableNixCommand [ "nix-command" ])
              ++ (lib.optionals cfg.enableFlakes [ "flakes" ])
              ++ cfg.extraExperimentalFeatures;

          # Trust flake-provided nixConfig (e.g., extra-experimental-features)
          accept-flake-config = cfg.acceptFlakeConfig;

          # Trusted users for Nix daemon
          trusted-users = [ "@admin" ];
        }
        // lib.optionalAttrs (extraSubstituters != [ ]) {
          extra-substituters = extraSubstituters;
        }
        // lib.optionalAttrs (extraTrustedPublicKeys != [ ]) {
          extra-trusted-public-keys = extraTrustedPublicKeys;
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

  home.ifEnabled = { cfg, ... }:
    let
      factCaches = config.facts.binaryCaches or { };
      extraSubstituters = lib.unique (cfg.binaryCaches.substituters ++ (factCaches.substituters or [ ]));
      extraTrustedPublicKeys = lib.unique (cfg.binaryCaches.trustedPublicKeys ++ (factCaches.trustedPublicKeys or [ ]));
    in
    {
      # Home Manager Nix settings
      nix.settings = {
        experimental-features =
          (lib.optionals cfg.enableNixCommand [ "nix-command" ])
            ++ (lib.optionals cfg.enableFlakes [ "flakes" ])
            ++ cfg.extraExperimentalFeatures;

        # Trust flake-provided nixConfig in user sessions
        accept-flake-config = cfg.acceptFlakeConfig;
      }
      // lib.optionalAttrs (extraSubstituters != [ ]) {
        extra-substituters = extraSubstituters;
      }
      // lib.optionalAttrs (extraTrustedPublicKeys != [ ]) {
        extra-trusted-public-keys = extraTrustedPublicKeys;
      };
    };
}

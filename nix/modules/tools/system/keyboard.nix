{ delib, lib, ... }:

# macOS keyboard/input preferences separated from GUI styling.

delib.module {
  name = "tools.system.keyboard";

  options = with delib; moduleOptions {
    enable = boolOption false;

    keyRepeat = {
      enable = boolOption true;
      # Office used 1, but 2 keeps the fast feel without being as aggressive.
      rate = intOption 2;
      initialDelay = intOption 15;
      pressAndHold = boolOption false;
    };

    keyboard = {
      useStandardFunctionKeys = boolOption true;
    };
  };

  darwin.ifEnabled = { cfg, ... }: {
    system.defaults.NSGlobalDomain =
      lib.optionalAttrs cfg.keyRepeat.enable
        {
          KeyRepeat = cfg.keyRepeat.rate;
          InitialKeyRepeat = cfg.keyRepeat.initialDelay;
          ApplePressAndHoldEnabled = cfg.keyRepeat.pressAndHold;
        }
      // {
        "com.apple.keyboard.fnState" = cfg.keyboard.useStandardFunctionKeys;
      };
  };
}

{ delib, ... }:

delib.module {
  name = "brew-nix";

  darwin.always = { ... }: {
    # brew-nix module and homebrew are already imported at the system level
    # This module can be used for additional brew-specific configuration if needed
  };
}

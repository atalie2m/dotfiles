{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Home base rice mirrors host defaults, but is inheritance-only to keep
  # Retained as an in-repo composition tree; not exported from the root flake.
delib.rice {
  name = "base";
  inherits = [ ];
  inheritanceOnly = true;
  myconfig = bundles.base;
}

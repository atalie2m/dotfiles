{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Home partial rice mirrors host defaults, but is inheritance-only to keep
  # Retained as an in-repo composition tree; not exported from the root flake.
delib.rice {
  name = "partial";
  inherits = [ "base" "darwin" "dev" ];
  inheritanceOnly = true;
  myconfig = bundles.partialOverride;
}

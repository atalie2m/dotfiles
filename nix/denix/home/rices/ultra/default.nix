{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Home ultra rice mirrors host defaults, but is inheritance-only to keep
  # Retained as an in-repo composition tree; not exported from the root flake.
delib.rice {
  name = "ultra";
  inherits = [ "base" "darwin" "dev" ];
  inheritanceOnly = true;
  myconfig = bundles.ultraOverride;
}

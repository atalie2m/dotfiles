{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Partial rice: keep the dev stack while selectively overriding tool toggles.
delib.rice {
  name = "partial";
  inherits = [ "base" "darwin" "dev" ];
  myconfig = bundles.partialOverride;
}

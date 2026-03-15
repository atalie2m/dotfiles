{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Base rice: cross-platform essentials.
delib.rice {
  name = "base";
  inherits = [ ];
  myconfig = bundles.base;
}

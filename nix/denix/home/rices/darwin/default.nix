{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Home darwin rice mirrors host defaults, but is inheritance-only to keep
  # Retained as an in-repo composition tree; not exported from the root flake.
delib.rice {
  name = "darwin";
  inherits = [ "base" ];
  inheritanceOnly = true;
  myconfig = bundles.darwin;
}

{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Darwin rice: macOS-specific base integrations.
delib.rice {
  name = "darwin";
  inherits = [ "base" ];
  myconfig = bundles.darwin;
}

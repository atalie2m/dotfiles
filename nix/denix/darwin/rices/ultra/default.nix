{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Ultra rice: complete development and productivity environment.
delib.rice {
  name = "ultra";
  inherits = [ "base" "darwin" "dev" ];
  myconfig = bundles.ultraOverride;
}

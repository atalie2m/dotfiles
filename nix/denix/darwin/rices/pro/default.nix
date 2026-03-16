{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Pro rice: full stack without VS Code.
delib.rice {
  name = "pro";
  inherits = [ "base" "darwin" "dev" ];
  myconfig = bundles.proOverride;
}

{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Dev rice: editor and workstation stack.
delib.rice {
  name = "dev";
  inherits = [ "base" ];
  myconfig = bundles.dev;
}

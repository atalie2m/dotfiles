args@{ ... }:

let
  mkDarwinHost = import ../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  name = "mn_mac";
  rice = "full";
  machineKey = "mn_mac";
}

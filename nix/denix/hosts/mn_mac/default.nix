args@{ ... }:

let
  mkDarwinHost = import ../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  name = "mn_mac";
  rice = "mn";
  machineKey = "mn_mac";
}

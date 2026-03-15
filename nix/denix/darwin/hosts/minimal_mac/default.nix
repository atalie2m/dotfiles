args:

let
  mkDarwinHost = import ../../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  name = "minimal_mac";
  rice = "minimum";
  machineKey = "minimal_mac";
  system = "aarch64-darwin";
}

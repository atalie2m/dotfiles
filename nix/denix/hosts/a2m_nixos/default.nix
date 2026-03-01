args@{ ... }:

let
  mkNixosHost = import ../../lib/mk-nixos-host.nix args;
in
mkNixosHost {
  name = "a2m_nixos";
  rice = "minimum";
  machineKey = "a2m_nixos";
}

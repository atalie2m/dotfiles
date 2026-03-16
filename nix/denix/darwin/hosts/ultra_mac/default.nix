args:

let
  inherit (args) hostCatalog;
  host = hostCatalog.hosts.ultra_mac;
  mkDarwinHost = import ../../../lib/mk-darwin-host.nix args;
in
mkDarwinHost {
  inherit (host) name machineKey system extraMyconfig;
  rice = host.defaultRice;
}

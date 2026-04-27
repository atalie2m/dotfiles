{ dotmod, config, lib, ... }:

# Manage macOS host naming from the canonical host model.

(dotmod.mkModule { inherit config; }) {
  path = "tools.system.hostnames";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  darwinOnEnable = { myconfig, ... }:
    let
      m = myconfig.hostContext.machine or { };
    in
    {
      networking =
        { }
        // lib.optionalAttrs (m.computerName != null) {
          computerName = m.computerName;
        }
        // lib.optionalAttrs (m.localHostName != null) {
          localHostName = m.localHostName;
        }
        // lib.optionalAttrs (m.hostName != null) {
          hostName = m.hostName;
        }
        // lib.optionalAttrs (m.domain != null) {
          domain = m.domain;
        };
    };
}

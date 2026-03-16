{ delib, lib, ... }:

# Manage macOS host naming from the canonical host model.

delib.module {
  name = "tools.system.hostnames";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  darwin.ifEnabled = { myconfig, ... }:
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

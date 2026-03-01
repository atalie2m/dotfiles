{ delib, lib, ... }:

# Manage macOS host naming from facts.machines.<host>
delib.module {
  name = "tools.system.hostnames";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.system.hostnames.enable = lib.mkDefault parent.enable;
    };
  };

  darwin.ifEnabled = { myconfig, ... }:
    let
      m = myconfig.facts.machine or { };
    in
    {
      networking =
        { }
        // lib.optionalAttrs (m ? computerName && lib.isString m.computerName && m.computerName != "") {
          computerName = m.computerName;
        }
        // lib.optionalAttrs (m ? localHostName && lib.isString m.localHostName && m.localHostName != "") {
          localHostName = m.localHostName;
        }
        // lib.optionalAttrs (m ? hostName && lib.isString m.hostName && m.hostName != "") {
          hostName = m.hostName;
        }
        // lib.optionalAttrs (m ? domain && lib.isString m.domain && m.domain != "") {
          domain = m.domain;
        };
    };
}

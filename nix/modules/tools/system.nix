{ dotmod, config, ... }:

# System integration tool group

(dotmod.mkModule { inherit config; }) {
  path = "tools.system";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };
}

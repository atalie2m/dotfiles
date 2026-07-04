{ dotmod, config, ... }:

# Core CLI tool group

(dotmod.mkModule { inherit config; }) {
  path = "tools.core";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };
}

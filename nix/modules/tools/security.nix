{ dotmod, config, ... }:

# Security tool group

(dotmod.mkModule { inherit config; }) {
  path = "tools.security";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };
}

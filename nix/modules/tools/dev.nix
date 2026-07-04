{ dotmod, config, ... }:

# Development tool group

(dotmod.mkModule { inherit config; }) {
  path = "tools.dev";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };
}

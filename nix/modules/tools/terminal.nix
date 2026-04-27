{ dotmod, config, ... }:

# Terminal tool group

(dotmod.mkModule { inherit config; }) {
  path = "tools.terminal";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };
}

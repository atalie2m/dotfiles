{ dotmod, config, ... }:

# AI coding agent tool group

(dotmod.mkModule { inherit config; }) {
  path = "tools.aiCodingAgent";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };
}

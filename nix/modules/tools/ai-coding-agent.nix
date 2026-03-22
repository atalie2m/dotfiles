{ delib, ... }:

# AI coding agent tool group

delib.module {
  name = "tools.aiCodingAgent";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}

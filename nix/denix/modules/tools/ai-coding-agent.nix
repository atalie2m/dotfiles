{ delib, ... }:

# AI coding agent tool group
# Individual tools default to this group toggle unless explicitly overridden.
delib.module {
  name = "tools.aiCodingAgent";

  options.tools.aiCodingAgent = with delib.options; {
    enable = boolOption false;
  };
}

{ delib, ... }:

# Editor tool group

delib.module {
  name = "tools.editor";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };
}

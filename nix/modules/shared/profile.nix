{ lib, ... }:

{
  options.myconfig.profile = {
    name = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
    };

    available = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
    };
  };
}

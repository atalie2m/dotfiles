{ delib, lib, ... }:

let
  types = lib.types;
  stateVersionType = types.submodule {
    options = {
      home = lib.mkOption {
        type = types.str;
        readOnly = true;
      };
      darwin = lib.mkOption {
        type = types.int;
        readOnly = true;
      };
      nixos = lib.mkOption {
        type = types.str;
        readOnly = true;
      };
    };
  };
  userType = types.submodule {
    options = {
      username = lib.mkOption {
        type = types.str;
        readOnly = true;
      };
      fullName = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      email = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      homeDirectory = lib.mkOption {
        type = types.str;
        readOnly = true;
      };
      configDirectory = lib.mkOption {
        type = types.str;
        readOnly = true;
      };
      stateVersion = lib.mkOption {
        type = stateVersionType;
        readOnly = true;
      };
    };
  };
in
delib.module {
  name = "hostContext";

  options.hostContext = {
    name = lib.mkOption {
      type = types.str;
      readOnly = true;
    };
    machineKey = lib.mkOption {
      type = types.str;
      readOnly = true;
    };
    system = lib.mkOption {
      type = types.str;
      readOnly = true;
    };
    os = lib.mkOption {
      type = types.str;
      readOnly = true;
    };
    arch = lib.mkOption {
      type = types.str;
      readOnly = true;
    };
    user = lib.mkOption {
      type = userType;
      readOnly = true;
    };
    machine = lib.mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
    };
    machines = lib.mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
    };
    binaryCaches = {
      substituters = lib.mkOption {
        type = types.listOf types.str;
        readOnly = true;
      };
      trustedPublicKeys = lib.mkOption {
        type = types.listOf types.str;
        readOnly = true;
      };
    };
  };
}

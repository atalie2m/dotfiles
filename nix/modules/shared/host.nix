{ lib, ... }:

let
  types = lib.types;
  machineType = types.submodule {
    options = {
      homeDirectory = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      computerName = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      localHostName = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      hostName = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      domain = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      keyboardType = lib.mkOption {
        type = types.nullOr (types.enum [ "ansi" "jis" ]);
        readOnly = true;
      };
      extra = lib.mkOption {
        type = types.attrsOf types.anything;
        readOnly = true;
      };
    };
  };
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
    };
  };
  gitType = types.submodule {
    options = {
      fullName = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      email = lib.mkOption {
        type = types.nullOr types.str;
        readOnly = true;
      };
      signingKey = lib.mkOption {
        type = types.nullOr types.str;
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
      git = lib.mkOption {
        type = gitType;
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
{
  options.myconfig.hostContext = {
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
      type = machineType;
      readOnly = true;
    };
    machines = lib.mkOption {
      type = types.attrsOf machineType;
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

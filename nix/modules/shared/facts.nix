{ delib, lib, ... }:

# Local machine facts (sourced from inputs.local/facts.nix)
delib.module {
  name = "facts";

  options.facts =
    let
      types = lib.types;
      machineType = types.submodule {
        options = {
          homeDirectory = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          computerName = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          localHostName = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          hostName = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          domain = lib.mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          extra = lib.mkOption {
            type = types.attrsOf types.anything;
            default = { };
          };
        };
      };
    in
    {
      user = lib.mkOption {
        type = types.submodule {
          options = {
            username = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            fullName = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            email = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            homeDirectory = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            configDirectory = lib.mkOption {
              type = types.nullOr types.str;
              default = null;
            };
            stateVersion = lib.mkOption {
              type = types.submodule {
                options = {
                  home = lib.mkOption {
                    type = types.nullOr types.str;
                    default = null;
                  };
                  darwin = lib.mkOption {
                    type = types.nullOr types.int;
                    default = null;
                  };
                };
              };
              default = { };
            };
          };
        };
        default = { };
      };

      machines = lib.mkOption {
        type = types.attrsOf machineType;
        default = { };
      };

      binaryCaches = {
        substituters = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
        trustedPublicKeys = lib.mkOption {
          type = types.listOf types.str;
          default = [ ];
        };
      };
    };
}

{ delib, lib, ... }:

# Local machine facts (sourced from inputs.local/facts.nix)
delib.module {
  name = "facts";

  options.facts =
    let
      types = lib.types;
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
                  nixos = lib.mkOption {
                    type = types.nullOr types.str;
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
        type = types.attrsOf types.anything;
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

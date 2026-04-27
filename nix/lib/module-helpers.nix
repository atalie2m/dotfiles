{ lib }:

let
  callOrEmpty = fn: args:
    if fn == null then { } else fn args;

  enabledAt = config: path:
    (lib.attrByPath (lib.splitString "." path) { } config.myconfig).enable or false;

  optionPathFor = path:
    [ "myconfig" ] ++ lib.splitString "." path;

  optionalModule = body: args:
    lib.optional (body != null) ({ ... }: body args);
in
rec {
  inherit (lib.types)
    anything
    attrs
    int
    path
    str
    ;

  boolOption = default: lib.mkOption {
    type = lib.types.bool;
    inherit default;
  };

  strOption = default: lib.mkOption {
    type = lib.types.str;
    inherit default;
  };

  intOption = default: lib.mkOption {
    type = lib.types.int;
    inherit default;
  };

  attrsOption = default: lib.mkOption {
    type = lib.types.attrs;
    inherit default;
  };

  attrsOfOption = type: default: lib.mkOption {
    type = lib.types.attrsOf type;
    inherit default;
  };

  listOfOption = type: default: lib.mkOption {
    type = lib.types.listOf type;
    inherit default;
  };

  moduleOptions = options: options;

  mkModule = moduleArgs:
    { path
    , options ? { }
    , myconfigOnEnable ? null
    , homeOnEnable ? null
    , homeAlways ? null
    , darwinOnEnable ? null
    , darwinAlways ? null
    ,
    }:
    let
      inherit (moduleArgs) config;
      cfg = lib.attrByPath (lib.splitString "." path) { } config.myconfig;
      args = {
        inherit cfg config;
        myconfig = config.myconfig;
      };
      darwinAlwaysAttrs = callOrEmpty darwinAlways args;
    in
    {
      imports = darwinAlwaysAttrs.imports or [ ];
      options = lib.setAttrByPath (optionPathFor path) options;

      config = lib.mkMerge [
        (removeAttrs darwinAlwaysAttrs [ "imports" ])
        (lib.optionalAttrs (homeAlways != null) {
          home-manager.sharedModules = optionalModule homeAlways args;
        })
        (lib.mkIf (enabledAt config path) (lib.mkMerge [
          (lib.optionalAttrs (myconfigOnEnable != null) {
            myconfig = callOrEmpty myconfigOnEnable args;
          })
          (callOrEmpty darwinOnEnable args)
          (lib.optionalAttrs (homeOnEnable != null) {
            home-manager.sharedModules = optionalModule homeOnEnable args;
          })
        ]))
      ];
    };
}

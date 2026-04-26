{ delib, lib, dotlib, pkgs, repoPaths, ... }:

let
  toolCatalog = import (repoPaths.catalog + "/tools/nixpkgs.nix");

  systemName =
    if pkgs.stdenv.isDarwin then "darwin"
    else if pkgs.stdenv.isLinux then "linux"
    else "other";

  resolvePkg = spec:
    dotlib.resolveCatalogPkg {
      inherit pkgs systemName spec;
    };

  mkToolModule = catalogName: spec:
    let
      toolName = spec.tool or catalogName;
      toolKey = "${spec.group}.${toolName}";
      supportedSystems = spec.systems or [ "darwin" "linux" ];
      package = resolvePkg spec;
      isSupportedSystem = builtins.elem systemName supportedSystems;
    in
    delib.module {
      name = "tools.${spec.group}.${toolName}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };

      myconfig.ifEnabled = { ... }:
        lib.mkMerge [
          (lib.optionalAttrs (spec ? unfree && spec.unfree != [ ]) (
            dotlib.requireUnfree spec.unfree
          ))
        ];

      home.ifEnabled = { ... }: {
        assertions = lib.optional (isSupportedSystem && package == null) {
          assertion = false;
          message = dotlib.nixCatalogFailureMessage {
            inherit toolKey systemName spec;
          };
        };

        home.packages = lib.optional (isSupportedSystem && package != null) package;
      };
    };
in
{
  imports = lib.mapAttrsToList mkToolModule toolCatalog;
}

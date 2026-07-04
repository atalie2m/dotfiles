{ dotmod, config, lib, dotlib, pkgs, repoPaths, ... }:

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
    (dotmod.mkModule { inherit config; }) {
      path = "tools.${spec.group}.${toolName}";

      options = with dotmod; moduleOptions {
        enable = boolOption false;
      };

      myconfigOnEnable = { ... }:
        lib.mkMerge [
          (lib.optionalAttrs (spec ? unfree && spec.unfree != [ ]) (
            dotlib.requireUnfree spec.unfree
          ))
        ];

      homeOnEnable = { ... }: {
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

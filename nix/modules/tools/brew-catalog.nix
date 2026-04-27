{ dotmod, config, lib, dotlib, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  brewCatalog = lib.filterAttrs (_: spec: spec.mode == "catalog") homebrewOwnership;

  mkBrewToolModule = _: spec:
    (dotmod.mkModule { inherit config; }) {
      path = "tools.${spec.group}.${spec.tool}";

      options = with dotmod; moduleOptions {
        enable = boolOption false;
      };

      myconfigOnEnable = { myconfig, ... }:
        dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec spec);

      darwinOnEnable = { ... }: {
        assertions = lib.optional (!dotlib.hasHomebrewInstallPayload spec) {
          assertion = false;
          message = dotlib.homebrewCatalogFailureMessage {
            toolKey = "${spec.group}.${spec.tool}";
          };
        };
      };
    };
in
{
  imports = lib.mapAttrsToList mkBrewToolModule brewCatalog;
}

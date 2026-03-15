{ delib, lib, dotlib, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  brewCatalog = lib.filterAttrs (_: spec: spec.mode == "catalog") homebrewOwnership;

  mkBrewToolModule = _: spec:
    delib.module {
      name = "tools.${spec.group}.${spec.tool}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };

      myconfig = {
        always = dotlib.mkEnableDefault "tools.${spec.group}.${spec.tool}.enable";
        ifEnabled = { myconfig, ... }:
          dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec spec);
      };

      darwin.ifEnabled = { ... }: {
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

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
        dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpecForHost { inherit myconfig spec; });

      darwinOnEnable = { myconfig, ... }: {
        assertions = lib.optional (!dotlib.hasHomebrewInstallPayload spec) {
          assertion = false;
          message = dotlib.homebrewCatalogFailureMessage {
            toolKey = "${spec.group}.${spec.tool}";
          };
        };
        warnings = lib.optional
          (dotlib.homebrewSpecRequiresUnavailableHostCapability { inherit myconfig spec; })
          "${spec.group}.${spec.tool} is enabled but skipped because full Xcode.app is not available.";
      };
    };
in
{
  imports = lib.mapAttrsToList mkBrewToolModule brewCatalog;
}

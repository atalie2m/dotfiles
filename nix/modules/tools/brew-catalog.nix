{ delib, lib, dotlib, repoPaths, ... }:

let
  brewCatalog = import (repoPaths.catalog + "/tools/homebrew.nix");

  mkBrewToolModule = toolName: spec:
    delib.module {
      name = "tools.${spec.group}.${toolName}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };

      myconfig = {
        always = dotlib.mkEnableDefault "tools.${spec.group}.${toolName}.enable";
        ifEnabled = { myconfig, ... }:
          dotlib.ifDarwin myconfig (dotlib.requireHomebrew {
            taps = spec.taps or [ ];
            brews = spec.brews or [ ];
            casks = spec.casks or [ ];
            masApps = spec.masApps or { };
          });
      };

      darwin.ifEnabled = { ... }: {
        assertions = lib.optional (!dotlib.hasHomebrewInstallPayload spec) {
          assertion = false;
          message = dotlib.homebrewCatalogFailureMessage {
            toolKey = "${spec.group}.${toolName}";
          };
        };
      };
    };
in
{
  imports = lib.mapAttrsToList mkBrewToolModule brewCatalog;
}

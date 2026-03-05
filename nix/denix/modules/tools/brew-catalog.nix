{ delib, lib, dotlib, ... }:

let
  brewCatalog = import ../../../data/tools/brew-catalog-data.nix;

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
    };
in
{
  imports = lib.mapAttrsToList mkBrewToolModule brewCatalog;
}

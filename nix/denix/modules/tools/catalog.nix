{ delib, lib, dotlib, pkgs, ... }:

let
  toolCatalog = import ../../../data/tools/catalog-data.nix;

  systemName =
    if pkgs.stdenv.isDarwin then "darwin"
    else if pkgs.stdenv.isLinux then "linux"
    else "other";

  resolvePkg = spec:
    let
      selected =
        if systemName == "darwin" then spec.pkgDarwin or spec.pkg or null
        else if systemName == "linux" then spec.pkgLinux or spec.pkg or null
        else spec.pkg or null;
      path =
        if builtins.isList selected then selected
        else if selected == null then null
        else [ selected ];
    in
    if path == null then null else lib.attrByPath path null pkgs;

  mkToolModule = toolName: spec:
    let
      optionPath = [ "tools" spec.group toolName "enable" ];
      supportedSystems = spec.systems or [ "darwin" "linux" ];
      package = resolvePkg spec;
      isSupportedSystem = builtins.elem systemName supportedSystems;
    in
    delib.module {
      name = "tools.${spec.group}.${toolName}";

      options = with delib; moduleOptions {
        enable = boolOption false;
      };

      myconfig =
        {
          always = dotlib.mkEnableDefault (lib.concatStringsSep "." optionPath);
          ifEnabled = { ... }:
            lib.mkMerge [
              (lib.optionalAttrs (spec ? unfree && spec.unfree != [ ]) (
                dotlib.requireUnfree spec.unfree
              ))
            ];
        };

      home.ifEnabled = { ... }: {
        home.packages = lib.optional (isSupportedSystem && package != null) package;
      };
    };
in
{
  imports = lib.mapAttrsToList mkToolModule toolCatalog;
}

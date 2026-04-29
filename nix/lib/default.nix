{ lib }:

let
  hostModel = import ./host-model.nix;
  getHostSystem = myconfig:
    myconfig.hostContext.system or "";
  getHostOs = myconfig:
    myconfig.hostContext.os or "";
  normalizeCatalogPkgPath = value:
    if value == null then null
    else if builtins.isList value then value
    else [ value ];
  selectedCatalogPkgField = systemName: spec:
    if systemName == "darwin" then
      if spec ? pkgDarwin then "pkgDarwin"
      else if spec ? pkg then "pkg"
      else null
    else if systemName == "linux" then
      if spec ? pkgLinux then "pkgLinux"
      else if spec ? pkg then "pkg"
      else null
    else if spec ? pkg then
      "pkg"
    else
      null;
  selectedCatalogPkgPath = systemName: spec:
    let
      field = selectedCatalogPkgField systemName spec;
    in
    if field == null then null else normalizeCatalogPkgPath spec.${field};
  selectedCatalogPkgDescription = systemName: spec:
    let
      field = selectedCatalogPkgField systemName spec;
      path = selectedCatalogPkgPath systemName spec;
      missingFields =
        if systemName == "darwin" then "pkgDarwin or pkg"
        else if systemName == "linux" then "pkgLinux or pkg"
        else "pkg";
    in
    if field == null then
      "${missingFields} is not set"
    else
      "${field}=pkgs.${lib.concatStringsSep "." (map builtins.toString path)}";
in
rec {
  inherit (hostModel)
    buildHostModel
    defaultStateVersion
    normalizeRawFacts
    parseSystem
    rawFactsChecks
    rawFactsChecksText
    renderBootstrapFacts
    ;

  mkEnableDefault = optionPath: { parent, ... }:
    lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault parent.enable);

  mkEnableDefaults = optionPaths: args:
    lib.mkMerge (map (optionPath: (lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault args.parent.enable))) optionPaths);

  requireHomebrew = { taps ? [ ], brews ? [ ], casks ? [ ], masApps ? { } }:
    lib.mkMerge [
      {
        # Prefer enabling Homebrew when a tool explicitly requires it.
        # Keep this weaker than explicit user values, but stronger than inherited mkDefault false.
        tools.system.nixHomebrew.enable = lib.mkOverride 900 true;
        tools.system.homebrewNative.enable = lib.mkOverride 900 true;
      }
      (lib.optionalAttrs (taps != [ ]) {
        tools.system.homebrewNative.taps = lib.mkAfter taps;
      })
      (lib.optionalAttrs (brews != [ ]) {
        tools.system.homebrewNative.brews = lib.mkAfter brews;
      })
      (lib.optionalAttrs (casks != [ ]) {
        tools.system.homebrewNative.casks = lib.mkAfter casks;
      })
      (lib.optionalAttrs (masApps != { }) {
        tools.system.homebrewNative.masApps = masApps;
      })
    ];

  requireHomebrewSpec = spec:
    requireHomebrew {
      taps = spec.taps or [ ];
      brews = spec.brews or [ ];
      casks = spec.casks or [ ];
      masApps = spec.masApps or { };
    };

  hostHasFullXcode = myconfig:
    let
      value = (((myconfig.hostContext or { }).machine or { }).extra or { }).fullXcode or false;
    in
    builtins.isBool value && value;

  homebrewSpecRequiresUnavailableHostCapability = { myconfig, spec }:
    (spec.requiresFullXcode or false) && !(hostHasFullXcode myconfig);

  requireHomebrewSpecForHost = { myconfig, spec }:
    lib.mkIf
      (!homebrewSpecRequiresUnavailableHostCapability { inherit myconfig spec; })
      (requireHomebrewSpec spec);

  requireUnfree = packages:
    lib.mkMerge [
      {
        nixpkgs.unfree.enable = lib.mkOverride 900 true;
        nixpkgs.unfree.allowAll = lib.mkOverride 900 false;
      }
      (lib.optionalAttrs (packages != [ ]) {
        nixpkgs.unfree.packages = lib.mkAfter packages;
      })
    ];

  resolveCatalogPkg =
    { pkgs
    , systemName
    , spec
    }:
    let
      path = selectedCatalogPkgPath systemName spec;
    in
    if path == null then null else lib.attrByPath path null pkgs;

  nixCatalogFailureMessage =
    { toolKey
    , systemName
    , spec
    }:
    "catalog entry ${toolKey} is enabled on ${systemName} but did not resolve to a Nix package (${selectedCatalogPkgDescription systemName spec})";

  hasHomebrewInstallPayload = spec:
    (spec.brews or [ ]) != [ ]
    || (spec.casks or [ ]) != [ ]
    || (spec.masApps or { }) != { };

  homebrewCatalogFailureMessage = { toolKey }:
    "Homebrew catalog entry ${toolKey} must declare at least one of brews, casks, or masApps.";

  ifDarwin = myconfig: attrs:
    lib.mkIf ((getHostOs myconfig) == "darwin" || lib.hasSuffix "-darwin" (getHostSystem myconfig)) attrs;

  ifLinux = myconfig: attrs:
    lib.mkIf ((getHostOs myconfig) == "linux" || lib.hasSuffix "-linux" (getHostSystem myconfig)) attrs;
}

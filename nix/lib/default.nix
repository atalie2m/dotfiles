{ lib }:

let
  getPlatform = myconfig:
    myconfig.facts.user.platform or myconfig.constants.platform or "";
in
{
  mkEnableDefault = optionPath: { parent, ... }:
    lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault parent.enable);

  mkEnableDefaults = optionPaths: args:
    lib.mkMerge (map (optionPath: (lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault args.parent.enable))) optionPaths);

  requireHomebrew = { taps ? [ ], brews ? [ ], casks ? [ ], masApps ? { } }:
    lib.mkMerge [
      {
        # Prefer enabling Homebrew when a tool explicitly requires it.
        # Keep this weaker than explicit user values, but stronger than inherited mkDefault false.
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

  ifDarwin = myconfig: attrs:
    lib.mkIf (lib.hasSuffix "-darwin" (getPlatform myconfig)) attrs;

  ifLinux = myconfig: attrs:
    lib.mkIf (lib.hasSuffix "-linux" (getPlatform myconfig)) attrs;
}

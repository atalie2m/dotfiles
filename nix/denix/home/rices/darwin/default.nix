{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.darwin;
in
# Home darwin rice mirrors host defaults, but is inheritance-only to keep
  # homeConfigurations at one entry per host.
delib.rice {
  name = "darwin";
  inherits = profile.inherits;
  inheritanceOnly = true;
  inherit (profile) myconfig;
}

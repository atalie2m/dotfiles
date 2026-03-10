{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.partial;
in
# Partial rice: keep the dev stack while selectively overriding tool toggles.
delib.rice {
  name = "partial";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}

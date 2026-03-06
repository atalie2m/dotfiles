{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.full;
in
# Full rice: Complete development and productivity environment
delib.rice {
  name = "full";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}

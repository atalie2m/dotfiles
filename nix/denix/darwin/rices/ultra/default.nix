{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.ultra;
in
# Ultra rice: complete development and productivity environment.
delib.rice {
  name = "ultra";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}

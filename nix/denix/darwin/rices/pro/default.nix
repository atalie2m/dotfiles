{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.pro;
in
# Pro rice: full stack minus VS Code.
delib.rice {
  name = "pro";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}

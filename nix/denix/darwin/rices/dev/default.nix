{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.dev;
in
# Dev rice: editor and workstation stack.
delib.rice {
  name = "dev";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}

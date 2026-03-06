{ delib, dotlib, ... }:

let
  profile = dotlib.riceProfiles.darwin;
in
# Darwin rice: macOS-specific base integrations.
delib.rice {
  name = "darwin";
  inherits = profile.inherits;
  inherit (profile) myconfig;
}

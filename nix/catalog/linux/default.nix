{ lib }:

let
  hostCatalog = import ./hosts.nix;
  profiles = import ./profiles.nix { inherit lib; };

  targetNameFor = hostName: profileName:
    let
      host = hostCatalog.hosts.${hostName};
    in
    if profileName == host.defaultProfile then host.buildTarget else "${hostName}-${profileName}";
in
hostCatalog // {
  inherit profiles targetNameFor;
  profileNames = hostCatalog.supportedProfiles;
}

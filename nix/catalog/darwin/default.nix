{ lib }:

let
  hostCatalog = import ./hosts.nix;
  profiles = import ./bundles.nix { inherit lib; };
  policyLib = import ./policy-lib.nix { inherit lib; };
  workPolicy = import ./work-policy.nix;

  targetNameFor = hostName: profileName:
    let
      host = hostCatalog.hosts.${hostName};
    in
    if profileName == host.defaultProfile then host.buildTarget else "${hostName}-${profileName}";
in
hostCatalog // {
  inherit policyLib profiles targetNameFor workPolicy;
  profileNames = hostCatalog.supportedProfiles;
}

{ factsFile }:

let
  hostModel = import ../../lib/host-model.nix;
  facts = import factsFile;
  hasRemovedNixosStateVersion =
    builtins.isAttrs facts
    && facts ? user
    && builtins.isAttrs facts.user
    && facts.user ? stateVersion
    && builtins.isAttrs facts.user.stateVersion
    && facts.user.stateVersion ? nixos;
in
if hasRemovedNixosStateVersion then
  "facts.migration|fail|facts.user.stateVersion.nixos has been removed; delete it from facts.nix"
else
  hostModel.rawFactsChecksText facts

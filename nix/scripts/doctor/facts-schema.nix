{ factsFile }:

let
  hostModel = import ../../lib/host-model.nix;
  facts = import factsFile;
in
hostModel.rawFactsChecksText facts

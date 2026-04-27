{ username, exampleHost ? "own_mac" }:

let
  hostModel = import ../../lib/host-model.nix;
in
hostModel.renderBootstrapFacts {
  inherit username exampleHost;
}

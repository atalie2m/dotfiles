{ dotmod, config, inputs, pkgs, ... }:

# Herdr agent multiplexer, packaged through the upstream Nix flake.

(dotmod.mkModule { inherit config; }) {
  path = "tools.aiCodingAgent.herdr";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  homeOnEnable = { ... }: {
    home.packages = [ inputs.herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr ];
  };
}

{ dotmod, config, dotlib, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."aiCodingAgent.claudeCode";
in

# Claude Code, installed through the latest-first Homebrew cask.

(dotmod.mkModule { inherit config; }) {
  path = "tools.aiCodingAgent.claudeCode";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  myconfigOnEnable = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);
}

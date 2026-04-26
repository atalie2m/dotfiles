{ delib, dotlib, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."aiCodingAgent.claudeCode";
in

# Claude Code, installed through the latest-first Homebrew cask.

delib.module {
  name = "tools.aiCodingAgent.claudeCode";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig.ifEnabled = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);
}

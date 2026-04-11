{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Partial rice: dev stack with selective AI overrides; VS Code HM off (use ultra for the module, then apply with `dotfiles sync vscode`).
delib.rice {
  name = "partial";
  inherits = [ "base" "darwin" "dev" ];
  myconfig = bundles.partialOverride;
}

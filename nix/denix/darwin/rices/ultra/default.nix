{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Ultra rice: full dev stack plus VS Code HM and bulk extensions from apps/vscode/; apply profile state manually with `dotfiles sync vscode`.
delib.rice {
  name = "ultra";
  inherits = [ "base" "darwin" "dev" ];
  myconfig = bundles.ultraOverride;
}

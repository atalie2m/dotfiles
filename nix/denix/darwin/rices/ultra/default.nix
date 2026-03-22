{ delib, ... }:

let
  bundles = import ../../../lib/capability-bundles.nix;
in
# Ultra rice: full dev stack plus VS Code HM, activation sync, and bulk extensions from apps/vscode/; other stock rices omit the VS Code module.
delib.rice {
  name = "ultra";
  inherits = [ "base" "darwin" "dev" ];
  myconfig = bundles.ultraOverride;
}

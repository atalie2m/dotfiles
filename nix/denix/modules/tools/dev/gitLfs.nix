{ delib, lib, ... }:

# tools.dev.gitLfs tool

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.dev.gitLfs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.dev.gitLfs.enable";
  };

}

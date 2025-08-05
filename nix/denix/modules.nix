{ delib, ... }:
let
  modulePaths = delib.umport { path = ./modules; };
  mkModule = path: {
    name = builtins.replaceStrings [".nix"] [""] (builtins.baseNameOf path);
    value = import path { inherit delib; };
  };
  modules = builtins.listToAttrs (map mkModule modulePaths);
in
modules

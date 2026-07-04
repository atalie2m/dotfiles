{ lib, ... }:

let
  collectNixFiles = dir:
    lib.concatLists (
      lib.mapAttrsToList
        (name: type:
          let
            path = dir + "/${name}";
          in
          if type == "directory" then
            collectNixFiles path
          else if type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix" then
            [ path ]
          else
            [ ])
        (builtins.readDir dir)
    );
in
{
  imports = collectNixFiles ./.;
}

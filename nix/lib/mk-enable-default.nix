{ lib }:

optionPath: { parent, ... }:
lib.setAttrByPath (lib.splitString "." optionPath) (lib.mkDefault parent.enable)

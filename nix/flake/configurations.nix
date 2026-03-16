{ inputs, denix, dotlib, repoPaths }:

let
  mkConfigurations = { moduleSystem, paths }:
    let
      facts = import (inputs.local + "/facts.nix");
      username = (dotlib.normalizeRawFacts facts).user.username;
    in
    if username == null then
      throw "facts.user.username is required (set in ~/.config/dotfiles/facts.nix or override inputs.local)"
    else
      denix.lib.configurations {
        inherit moduleSystem;
        homeManagerUser = username;
        inherit paths;
        extensions = with denix.lib.extensions; [
          args
          (base.withConfig { args.enable = true; })
        ];
        specialArgs = { inherit inputs dotlib repoPaths; };
      };

  configurationPaths = {
    darwin = [
      ../../nix/modules
      ../../nix/denix/darwin/hosts
      ../../nix/denix/darwin/rices
    ];
  };

  mkLatestConfigurations = moduleSystem:
    mkConfigurations {
      inherit moduleSystem;
      paths = configurationPaths.${moduleSystem}
        or (throw "unsupported moduleSystem '${moduleSystem}'");
    };

  darwinConfigurations = mkLatestConfigurations "darwin";
in
{
  inherit darwinConfigurations;
}

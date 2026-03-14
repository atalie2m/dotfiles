{ inputs, denix, dotlib, repoPaths, localStub }:

let
  mkConfigurations = { moduleSystem, paths }:
    let
      facts = import (inputs.local + "/facts.nix");
      user = facts.user or { };
      username = user.username or "";
      _ =
        if username == "" then
          throw "facts.user.username is required (set in ~/.config/dotfiles/facts.nix or override inputs.local)"
        else
          null;
    in
    builtins.seq _ (denix.lib.configurations {
      inherit moduleSystem;
      homeManagerUser = username;
      inherit paths;
      extensions = with denix.lib.extensions; [
        args
        (base.withConfig { args.enable = true; })
      ];
      specialArgs = { inherit inputs dotlib repoPaths; };
    });

  configurationPaths = {
    darwin = [
      ../../nix/modules
      ../../nix/denix/darwin/hosts
      ../../nix/denix/darwin/rices
    ];
    nixos = [
      ../../nix/modules
      ../../nix/denix/nixos/hosts
      ../../nix/denix/nixos/rices
    ];
    home = [
      ../../nix/modules
      ../../nix/denix/home/hosts
      ../../nix/denix/home/rices
    ];
  };

  mkLatestConfigurations = moduleSystem:
    mkConfigurations {
      inherit moduleSystem;
      paths = configurationPaths.${moduleSystem}
        or (throw "unsupported moduleSystem '${moduleSystem}'");
    };

  darwinConfigurations = if localStub then { } else mkLatestConfigurations "darwin";
  homeConfigurations = if localStub then { } else mkLatestConfigurations "home";
  nixosConfigurations = if localStub then { } else mkLatestConfigurations "nixos";
in
{
  inherit
    mkConfigurations
    configurationPaths
    mkLatestConfigurations
    darwinConfigurations
    homeConfigurations
    nixosConfigurations
    ;
}

{ inputs, denix, dotlib, repoPaths }:

let
  hostCatalog = import ../../nix/denix/darwin/host-catalog.nix;

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
        specialArgs = { inherit inputs dotlib repoPaths hostCatalog; };
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

  pruneDefaultRiceAliases = configurations:
    let
      aliasesToRemove =
        builtins.filter
          (targetName: targetName != null && builtins.hasAttr targetName configurations)
          (map
            (hostName:
              let
                hostSpec = hostCatalog.hosts.${hostName};
                alias = "${hostName}-${hostSpec.defaultRice}";
              in
              if alias == hostSpec.buildTarget then null else alias)
            (builtins.attrNames hostCatalog.hosts));
    in
    builtins.removeAttrs configurations aliasesToRemove;

  darwinConfigurations = pruneDefaultRiceAliases (mkLatestConfigurations "darwin");
in
{
  inherit darwinConfigurations;
}

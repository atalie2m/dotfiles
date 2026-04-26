{ inputs
, repoPaths
, dotlib
, toolOwnershipLib
, darwinConfigurations
, mkDotfilesCliPackage
, mkDotfilesPackage
, mkSyncVscodeRustPackage
, mkPortableChecks
, mkPortableDevShell
, treefmtConfigFor
}:

{ pkgs, config, lib, ... }:
let
  dotfilesRoot = repoPaths.root;
  darwinTargetNames = lib.sort (a: b: a < b) (builtins.attrNames darwinConfigurations);
  toolOwnershipReports =
    map
      (targetName: toolOwnershipLib.report targetName darwinConfigurations.${targetName}.config)
      darwinTargetNames;
  toolOwnershipFailures = lib.concatMap (report: report.failureMessages) toolOwnershipReports;
  toolOwnershipFailureText = lib.concatStringsSep "\n" toolOwnershipFailures;
  nixCatalog = import (repoPaths.catalog + "/tools/nixpkgs.nix");
  catalogUnfreePackages = lib.unique (lib.concatMap (spec: spec.unfree or [ ]) (builtins.attrValues nixCatalog));
  catalogPkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) catalogUnfreePackages;
  };
  catalogSystemName =
    if pkgs.stdenv.isDarwin then "darwin"
    else if pkgs.stdenv.isLinux then "linux"
    else "other";
  catalogPackageFailures =
    lib.concatMap
      (catalogName:
        let
          spec = nixCatalog.${catalogName};
          toolName = spec.tool or catalogName;
          toolKey = "${spec.group}.${toolName}";
          supportedSystems = spec.systems or [ "darwin" "linux" ];
          isSupportedSystem = builtins.elem catalogSystemName supportedSystems;
          package = dotlib.resolveCatalogPkg {
            pkgs = catalogPkgs;
            systemName = catalogSystemName;
            inherit spec;
          };
        in
        lib.optional (isSupportedSystem && (package == null || !(lib.meta.availableOn catalogPkgs.stdenv.hostPlatform package)))
          (dotlib.nixCatalogFailureMessage {
            inherit toolKey spec;
            systemName = catalogSystemName;
          }))
      (builtins.attrNames nixCatalog);
  catalogPackageFailureText = lib.concatStringsSep "\n" catalogPackageFailures;
  catalogValidationFailureText =
    dotlib.nixCatalogFailureMessage {
      toolKey = "core.fakeTool";
      systemName = "darwin";
      spec = {
        group = "core";
        pkgDarwin = [ "missing" "package" ];
      };
    };
  brewNixOverlapReport = toolOwnershipLib.report "test-target" {
    myconfig.tools.system.brewNix = {
      enable = true;
      casks = {
        keyclu = "KeyClu.app";
      };
      extraCasks = { };
    };
    homebrew.casks = [ "keyclu" ];
  };
  brewNixDuplicateClaimReport = toolOwnershipLib.report "test-target" {
    myconfig.tools.system = {
      brewNix = {
        enable = true;
        casks = {
          keyclu = "KeyClu.app";
        };
        extraCasks = { };
      };
      keyclu.enable = true;
    };
    homebrew.casks = [ "keyclu" ];
  };

  mkDotfilesApp = { name, subcommand ? null, description }:
    let
      execLine =
        if subcommand == null
        then "exec ${dotfilesPackage}/bin/dotfiles \"$@\""
        else "exec ${dotfilesPackage}/bin/dotfiles ${subcommand} \"$@\"";
    in
    {
      type = "app";
      program = "${pkgs.writeShellScript "dotfiles-${name}" ''
        if [[ -z "''${DOTFILES_ROOT:-}" ]]; then
          pwd_root="$(pwd)"
          if [[ -f "$pwd_root/flake.nix" && -d "$pwd_root/scripts" ]]; then
            export DOTFILES_ROOT="$pwd_root"
          fi
        fi
        if [[ -z "''${DOTFILES_ROOT:-}" ]] && command -v git >/dev/null 2>&1; then
          candidate_root="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
          if [[ -n "$candidate_root" && -f "$candidate_root/flake.nix" && -d "$candidate_root/scripts" ]]; then
            export DOTFILES_ROOT="$candidate_root"
          fi
        fi
        export DOTFILES_ROOT="''${DOTFILES_ROOT:-${dotfilesRoot}}"
        ${execLine}
      ''}";
      meta.description = description;
    };

  dotfilesCli = mkDotfilesCliPackage pkgs;
  syncVscodeRust = mkSyncVscodeRustPackage pkgs;
  dotfilesPackage = mkDotfilesPackage {
    inherit pkgs dotfilesCli syncVscodeRust;
  };
  portableChecks = mkPortableChecks {
    inherit pkgs syncVscodeRust dotfilesPackage;
    formatterWrapper = config.treefmt.build.wrapper;
  };
in
{
  treefmt = treefmtConfigFor pkgs;

  formatter = config.treefmt.build.wrapper;

  checks = portableChecks // {
    treefmt = lib.mkForce portableChecks.treefmt;
    toolOwnership = pkgs.runCommand "tool-ownership-check" { } ''
                if [ ${toString (builtins.length toolOwnershipFailures)} -ne 0 ]; then
                  cat >&2 <<'EOF_TOOL_OWNERSHIP'
      ${toolOwnershipFailureText}
      EOF_TOOL_OWNERSHIP
                  exit 1
                fi
                touch "$out"
    '';

    catalogPolicy =
      let
        _ =
          assert dotlib.hasHomebrewInstallPayload { casks = [ "keyclu" ]; };
          assert (!dotlib.hasHomebrewInstallPayload { taps = [ "homebrew/cask" ]; });
          assert lib.hasInfix "core.fakeTool" catalogValidationFailureText;
          assert lib.hasInfix "darwin" catalogValidationFailureText;
          assert brewNixOverlapReport.hasFailures;
          assert lib.any
            (message: lib.hasInfix "configured in both Homebrew and brew-nix" message)
            brewNixOverlapReport.failureMessages;
          assert lib.any
            (entry: entry.itemType == "cask" && entry.itemName == "keyclu")
            brewNixDuplicateClaimReport.duplicateHomebrewItems;
          null;
      in
      builtins.seq _ (pkgs.runCommand "catalog-policy-check" { } ''
        touch "$out"
      '');

    catalogPackages = pkgs.runCommand "catalog-package-check" { } ''
      if [ ${toString (builtins.length catalogPackageFailures)} -ne 0 ]; then
        cat >&2 <<'EOF_CATALOG_PACKAGES'
      ${catalogPackageFailureText}
      EOF_CATALOG_PACKAGES
        exit 1
      fi
      touch "$out"
    '';
  };

  devShells.default = mkPortableDevShell {
    inherit pkgs;
    formatterWrapper = config.treefmt.build.wrapper;
  };

  packages = {
    darwin-rebuild = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild;
    dotfiles = dotfilesPackage;
    dotfiles-cli = dotfilesCli;
    dotfiles-sync-vscode = syncVscodeRust;
  };

  apps = {
    dotfiles = mkDotfilesApp {
      name = "cli";
      description = "Unified dotfiles CLI (apply/update/doctor/bootstrap/export-clean/list-tools/matrix-tools/sync).";
    };
    update = mkDotfilesApp {
      name = "update";
      subcommand = "update";
      description = "Update flake inputs, run checks, and build host targets.";
    };
    list-tools = mkDotfilesApp {
      name = "list-tools";
      subcommand = "list-tools";
      description = "List effective myconfig.tools values for a host/rice.";
    };
    matrix-tools = mkDotfilesApp {
      name = "matrix-tools";
      subcommand = "matrix-tools";
      description = "Show effective myconfig.tools matrix across darwin targets.";
    };
    apply = mkDotfilesApp {
      name = "apply";
      subcommand = "apply";
      description = "Build or switch nix-darwin configurations.";
    };
    darwin-rebuild = {
      type = "app";
      program = "${inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild}/bin/darwin-rebuild";
      meta.description = "Pinned nix-darwin rebuild wrapper from this flake lock.";
    };
    doctor = mkDotfilesApp {
      name = "doctor";
      subcommand = "doctor";
      description = "Run dotfiles health checks.";
    };
    bootstrap = mkDotfilesApp {
      name = "bootstrap";
      subcommand = "bootstrap";
      description = "Initialize local facts/secrets and optionally apply.";
    };
    export-clean = mkDotfilesApp {
      name = "export-clean";
      subcommand = "export-clean";
      description = "Export a clean tracked copy without .git metadata or AppleDouble files.";
    };
    format = {
      type = "app";
      program = "${config.treefmt.build.wrapper}/bin/treefmt";
      meta.description = "Format Nix and shell files with treefmt.";
    };
  };
}

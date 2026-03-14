{ inputs
, repoPaths
, dotlib
, toolOwnershipLib
, darwinConfigurations
, mkSyncVscodeRustPackage
, mkPortableChecks
, mkPortableDevShell
, treefmtConfigFor
}:

{ pkgs, config, lib, ... }:
let
  scripts = repoPaths.scripts;
  dotfilesRoot = repoPaths.root;
  darwinTargetNames = lib.sort (a: b: a < b) (builtins.attrNames darwinConfigurations);
  toolOwnershipReports =
    map
      (targetName: toolOwnershipLib.report targetName darwinConfigurations.${targetName}.config)
      darwinTargetNames;
  toolOwnershipFailures = lib.concatMap (report: report.failureMessages) toolOwnershipReports;
  toolOwnershipFailureText = lib.concatStringsSep "\n" toolOwnershipFailures;
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
        then "exec ${scripts}/dotfiles.sh \"$@\""
        else "exec ${scripts}/dotfiles.sh ${subcommand} \"$@\"";
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

  syncVscodeRust = mkSyncVscodeRustPackage pkgs;
  portableChecks = mkPortableChecks {
    inherit pkgs syncVscodeRust;
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
  };

  devShells.default = mkPortableDevShell {
    inherit pkgs;
    formatterWrapper = config.treefmt.build.wrapper;
  };

  packages = {
    darwin-rebuild = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild;
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

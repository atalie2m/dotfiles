{ inputs
, repoPaths
, dotlib
, toolOwnershipLib
, darwinConfigurations
, homeConfigurations
, linuxHomeManagerModulePaths
, mkDotfilesCliPackage
, mkDotfilesPackage
, mkEditorSyncAppProgram
, mkSyncVscodeRustPackage
, mkPortableChecks
, mkPortableDevShell
, treefmtConfigFor
}:

{ pkgs, config, lib, ... }:
let
  dotfilesRoot = repoPaths.root;
  darwinTargetNames = lib.sort (a: b: a < b) (builtins.attrNames darwinConfigurations);
  darwinZshRuntimeFailures =
    lib.concatMap
      (targetName:
        let
          targetConfig = darwinConfigurations.${targetName}.config;
          userName = targetConfig.myconfig.hostContext.user.username;
          homeZsh = targetConfig.home-manager.users.${userName}.programs.zsh;
          shellConfig = (targetConfig.myconfig.tools or { }).shell or { };
          systemShell = targetConfig.users.users.${userName}.shell or null;
        in
        lib.optional
          (homeZsh.enable && !lib.hasInfix "darwin-system-zsh" (toString homeZsh.package))
          "${targetName}: Home Manager zsh must use darwin-system-zsh"
        ++ lib.optional
          ((shellConfig.manageSystemShells or false)
          && (systemShell == null || !lib.hasInfix "darwin-system-zsh" (toString systemShell)))
          "${targetName}: managed login zsh must use darwin-system-zsh")
      darwinTargetNames;
  darwinZshRuntimeFailureText = lib.concatStringsSep "\n" darwinZshRuntimeFailures;
  listIndexOf = needle: values:
    let
      go = index: remaining:
        if remaining == [ ] then
          null
        else if builtins.head remaining == needle then
          index
        else
          go (index + 1) (builtins.tail remaining);
    in
    go 0 values;
  homebrewShellEnvironmentFailures =
    lib.concatMap
      (targetName:
        let
          targetConfig = darwinConfigurations.${targetName}.config;
          hostSystem = targetConfig.myconfig.hostContext.system;
          userName = targetConfig.myconfig.hostContext.user.username;
          homeDirectory = targetConfig.myconfig.hostContext.user.homeDirectory;
          homeConfig = targetConfig.home-manager.users.${userName}.home;
          nixHomebrewEnabled = targetConfig.nix-homebrew.enable or false;
          nativePrefixKey =
            if hostSystem == "aarch64-darwin" then
              targetConfig.nix-homebrew.defaultArm64Prefix
            else
              targetConfig.nix-homebrew.defaultIntelPrefix;
          nativePrefix = targetConfig.nix-homebrew.prefixes.${nativePrefixKey};
          expectedPrefix = nativePrefix.prefix;
          expectedRepository = "${nativePrefix.library}/.homebrew-is-managed-by-nix";
          homebrewBin = "${expectedPrefix}/bin";
          homebrewSbin = "${expectedPrefix}/sbin";
          sessionPath = homeConfig.sessionPath or [ ];
          sessionVariables = homeConfig.sessionVariables or { };
          homebrewBinIndex = listIndexOf homebrewBin sessionPath;
          homebrewSbinIndex = listIndexOf homebrewSbin sessionPath;
          nixProfileBins = [
            "/etc/profiles/per-user/${userName}/bin"
            "${homeDirectory}/.nix-profile/bin"
          ];
          nixPathOrderFailures =
            lib.concatMap
              (nixProfileBin:
                let
                  nixProfileBinIndex = listIndexOf nixProfileBin sessionPath;
                in
                lib.optional
                  (nixProfileBinIndex != null && homebrewBinIndex != null && nixProfileBinIndex >= homebrewBinIndex)
                  "${targetName}: ${nixProfileBin} must precede ${homebrewBin} in home.sessionPath")
              nixProfileBins;
        in
        [
          (lib.optional (targetConfig.nix-homebrew.enableBashIntegration or true)
            "${targetName}: nix-homebrew bash integration must be disabled")
          (lib.optional (targetConfig.nix-homebrew.enableFishIntegration or true)
            "${targetName}: nix-homebrew fish integration must be disabled")
          (lib.optional (targetConfig.nix-homebrew.enableZshIntegration or true)
            "${targetName}: nix-homebrew zsh integration must be disabled")
        ]
        ++ lib.optionals nixHomebrewEnabled [
          (lib.optional (!(nativePrefix.enable or false))
            "${targetName}: native Homebrew prefix ${expectedPrefix} must be enabled")
          (lib.optional ((sessionVariables.HOMEBREW_PREFIX or null) != expectedPrefix)
            "${targetName}: HOMEBREW_PREFIX must match the evaluated native prefix")
          (lib.optional ((sessionVariables.HOMEBREW_CELLAR or null) != "${expectedPrefix}/Cellar")
            "${targetName}: HOMEBREW_CELLAR must match the evaluated native prefix")
          (lib.optional ((sessionVariables.HOMEBREW_REPOSITORY or null) != expectedRepository)
            "${targetName}: HOMEBREW_REPOSITORY must match the nix-homebrew library")
          (lib.optional (homebrewBinIndex == null)
            "${targetName}: home.sessionPath is missing ${homebrewBin}")
          (lib.optional (homebrewSbinIndex == null)
            "${targetName}: home.sessionPath is missing ${homebrewSbin}")
          (lib.optional
            (homebrewBinIndex != null && homebrewSbinIndex != null && homebrewSbinIndex != homebrewBinIndex + 1)
            "${targetName}: Homebrew bin and sbin entries must remain adjacent")
          nixPathOrderFailures
        ])
      darwinTargetNames;
  homebrewShellEnvironmentFailureText =
    lib.concatStringsSep "\n" (lib.flatten homebrewShellEnvironmentFailures);
  homebrewActivationFailures =
    lib.concatMap
      (targetName:
        let
          targetConfig = darwinConfigurations.${targetName}.config;
          homebrewConfig = targetConfig.homebrew;
          homebrewEnabled = homebrewConfig.enable or false;
        in
        lib.optionals homebrewEnabled [
          (lib.optional (homebrewConfig.onActivation.autoUpdate or true)
            "${targetName}: routine activation must not auto-update Homebrew")
          (lib.optional (homebrewConfig.onActivation.upgrade or true)
            "${targetName}: routine activation must not upgrade Homebrew packages")
          (lib.optional (!(homebrewConfig.global.brewfile or false))
            "${targetName}: manual brew bundle commands must use the generated Brewfile")
        ])
      darwinTargetNames;
  homebrewActivationFailureText =
    lib.concatStringsSep "\n" (lib.flatten homebrewActivationFailures);
  homeManagerTargetNames = lib.sort (a: b: a < b) (builtins.attrNames homeConfigurations);
  homeManagerTargetNamesText = lib.concatStringsSep ", " homeManagerTargetNames;
  linuxWorkbenchTarget = homeConfigurations.linux_workbench or null;
  linuxWorkbenchConfig =
    if linuxWorkbenchTarget == null then
      null
    else
      linuxWorkbenchTarget.config;
  linuxWorkbenchMinimalTarget = homeConfigurations.linux_workbench-minimal or null;
  toolOwnershipReports =
    map
      (targetName: toolOwnershipLib.report targetName darwinConfigurations.${targetName}.config)
      darwinTargetNames;
  toolOwnershipFailures = lib.concatMap (report: report.failureMessages) toolOwnershipReports;
  toolOwnershipFailureText = lib.concatStringsSep "\n" toolOwnershipFailures;
  nixCatalog = import (repoPaths.catalog + "/tools/nixpkgs.nix");
  localPackagesOverlay = import ../pkgs/overlay.nix;
  catalogUnfreePackages = lib.unique (lib.concatMap (spec: spec.unfree or [ ]) (builtins.attrValues nixCatalog));
  catalogPkgs = import inputs.nixpkgs {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) catalogUnfreePackages;
    overlays = [ localPackagesOverlay ];
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
  dotmod = import ../lib/module-helpers.nix { inherit lib; };
  homebrewCaskName = raw:
    if builtins.isAttrs raw then raw.name or ""
    else raw;
  evalHomebrewNativeModule = { casks, extraMyconfig ? { } }:
    lib.evalModules {
      specialArgs = {
        inherit dotmod lib repoPaths;
      };
      modules = [
        ../modules/tools/system/homebrew-native.nix
        ({ lib, ... }: {
          options = {
            homebrew = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            system.activationScripts.homebrew.text = lib.mkOption {
              type = lib.types.lines;
              default = "";
            };
            myconfig.tools.aiCodingAgent.codex.enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
            myconfig.tools.system.keyclu.enable = lib.mkOption {
              type = lib.types.bool;
              default = false;
            };
          };
          config.myconfig = lib.recursiveUpdate
            {
              tools.system.homebrewNative = {
                enable = true;
                inherit casks;
              };
            }
            extraMyconfig;
        })
      ];
    };
  codexHomebrewNativeModule =
    evalHomebrewNativeModule {
      casks = [ "codex" ];
      extraMyconfig.tools.aiCodingAgent.codex.enable = true;
    };
  codexFilteredHomebrewNativeModule =
    evalHomebrewNativeModule {
      casks = [ "codex" ];
    };
  keycluHomebrewNativeModule =
    evalHomebrewNativeModule {
      casks = [ "keyclu" ];
      extraMyconfig.tools.system.keyclu.enable = true;
    };
  keycluFilteredHomebrewNativeModule =
    evalHomebrewNativeModule {
      casks = [ "keyclu" ];
    };
  deniedPayloadHomebrewNativeModule =
    evalHomebrewNativeModule {
      casks = [
        "anydesk"
        "rustdesk"
        "teamviewer"
        "wireshark"
      ];
      extraMyconfig.tools.system.homebrewNative = {
        brews = [
          "mosh"
          "ngrok"
        ];
        deniedBrews = [
          "mosh"
          "ngrok"
        ];
        deniedCasks = [
          "anydesk"
          "rustdesk"
          "teamviewer"
          "wireshark"
        ];
      };
    };
  codexHomebrewNativeActivationText =
    codexHomebrewNativeModule.config.system.activationScripts.homebrew.text;
  nonCodexHomebrewNativeActivationText =
    keycluHomebrewNativeModule.config.system.activationScripts.homebrew.text;
  homeManagerGlobalPkgsFailures =
    lib.concatMap
      (targetName:
        let
          cfg = darwinConfigurations.${targetName}.config;
          usesGlobalPkgs = cfg.home-manager.useGlobalPkgs or false;
          users = cfg.home-manager.users or { };
        in
        lib.concatMap
          (userName:
            let
              userCfg = users.${userName};
              nixpkgsConfig = userCfg.nixpkgs.config or null;
              nixpkgsOverlays = userCfg.nixpkgs.overlays or null;
              nixpkgsConfigKeys =
                if nixpkgsConfig == null then [ ] else builtins.attrNames nixpkgsConfig;
              nixpkgsOverlayCount =
                if nixpkgsOverlays == null then 0 else builtins.length nixpkgsOverlays;
            in
            lib.optional (usesGlobalPkgs && (nixpkgsConfigKeys != [ ] || nixpkgsOverlayCount != 0))
              "${targetName}:${userName} sets Home Manager nixpkgs options while home-manager.useGlobalPkgs is true")
          (builtins.attrNames users))
      darwinTargetNames;
  homeManagerGlobalPkgsFailureText = lib.concatStringsSep "\n" homeManagerGlobalPkgsFailures;
  linuxHomeManagerModulePathStrings = map builtins.toString linuxHomeManagerModulePaths;
  forbiddenLinuxModuleInfixes = [
    "/nix/modules/tools/system/brew-nix.nix"
    "/nix/modules/tools/system/homebrew-native.nix"
    "/nix/modules/tools/system/hostnames.nix"
    "/nix/modules/tools/system/karabiner.nix"
    "/nix/modules/tools/system/keyboard.nix"
    "/nix/modules/tools/system/mac-app-util.nix"
    "/nix/modules/tools/system/macos-ui.nix"
    "/nix/modules/tools/system/nix-homebrew.nix"
    "/nix/modules/tools/terminal/rio.nix"
    "/nix/modules/tools/terminal/wezterm.nix"
  ];
  forbiddenLinuxModuleImports =
    lib.filter
      (path: lib.any (infix: lib.hasInfix infix path) forbiddenLinuxModuleInfixes)
      linuxHomeManagerModulePathStrings;
  linuxWorkbenchTools =
    if linuxWorkbenchConfig == null then
      { }
    else
      linuxWorkbenchConfig.myconfig.tools or { };
  linuxToolEnabled = path:
    (lib.attrByPath path { } linuxWorkbenchTools).enable or false;
  formatToolPath = path: lib.concatStringsSep "." path;
  requiredLinuxWorkbenchToolPaths = [
    [ "filesNavigation" "duf" ]
    [ "filesNavigation" "dust" ]
    [ "filesNavigation" "ncdu" ]
    [ "filesNavigation" "ouch" ]
    [ "filesNavigation" "rclone" ]
    [ "filesNavigation" "rsync" ]
    [ "filesNavigation" "yazi" ]
    [ "gitPersonal" "ghDash" ]
    [ "gitPersonal" "ghq" ]
    [ "gitPersonal" "gitAbsorb" ]
    [ "gitPersonal" "gitFilterRepo" ]
    [ "gitPersonal" "jujutsu" ]
    [ "gitPersonal" "mergiraf" ]
    [ "dataPersonal" "csvlens" ]
    [ "dataPersonal" "duckdb" ]
    [ "dataPersonal" "fq" ]
    [ "dataPersonal" "fx" ]
    [ "dataPersonal" "harlequin" ]
    [ "dataPersonal" "jc" ]
    [ "dataPersonal" "jless" ]
    [ "dataPersonal" "miller" ]
    [ "dataPersonal" "pgActivity" ]
    [ "dataPersonal" "usql" ]
    [ "httpApiPersonal" "httpie" ]
    [ "httpApiPersonal" "xh" ]
    [ "network" "grpcurl" ]
    [ "network" "websocat" ]
    [ "nixOperator" "nixIndex" ]
    [ "nixOperator" "nixInspect" ]
    [ "nixOperator" "nixInit" ]
    [ "nixOperator" "nixSearchTv" ]
    [ "nixOperator" "nixd" ]
    [ "nixOperator" "nurl" ]
    [ "shellUx" "entr" ]
    [ "shellUx" "gum" ]
    [ "shellUx" "mprocs" ]
    [ "shellUx" "navi" ]
    [ "shellUx" "vivid" ]
    [ "viewersPreview" "hexyl" ]
    [ "viewersPreview" "mdcat" ]
    [ "viewersPreview" "tealdeer" ]
    [ "containerK8sPersonal" "k9s" ]
    [ "containerK8sPersonal" "kubecolor" ]
    [ "containerK8sPersonal" "kubectl" ]
    [ "containerK8sPersonal" "kubie" ]
    [ "containerK8sPersonal" "stern" ]
    [ "observability" "bottom" ]
    [ "observability" "glances" ]
    [ "observability" "goss" ]
  ];
  missingLinuxWorkbenchTools =
    lib.filter (path: !(linuxToolEnabled path)) requiredLinuxWorkbenchToolPaths;
  missingLinuxWorkbenchToolsText =
    lib.concatStringsSep ", " (map formatToolPath missingLinuxWorkbenchTools);
  forbiddenLinuxWorkbenchToolPaths = [
    [ "aiCodingAgent" "codex" ]
    [ "containerK8sPersonal" "docker" ]
    [ "containerK8sPersonal" "lazydocker" ]
    [ "containerK8sPersonal" "podman" ]
    [ "dev" "bun" ]
    [ "tuiWorkspace" "lazydocker" ]
    [ "tuiWorkspace" "zellij" ]
  ];
  enabledForbiddenLinuxWorkbenchTools =
    lib.filter linuxToolEnabled forbiddenLinuxWorkbenchToolPaths;
  enabledForbiddenLinuxWorkbenchToolsText =
    lib.concatStringsSep ", " (map formatToolPath enabledForbiddenLinuxWorkbenchTools);
  forbiddenProjectToolchainCatalogEntries =
    lib.filter (name: builtins.hasAttr name nixCatalog) [
      "go"
      "nodejs"
      "opentofu"
      "terraform"
    ];
  linuxHomeManagerAssertions =
    let
      cfg = linuxWorkbenchConfig;
      minimalCfg =
        if linuxWorkbenchMinimalTarget == null then
          null
        else
          linuxWorkbenchMinimalTarget.config;
    in
    [
      {
        assertion = builtins.hasAttr "own_mac" darwinConfigurations && builtins.hasAttr "work_mac" darwinConfigurations;
        message = "expected Darwin outputs own_mac and work_mac to evaluate";
      }
      {
        assertion = linuxWorkbenchTarget != null && linuxWorkbenchMinimalTarget != null;
        message = "expected homeConfigurations.linux_workbench and linux_workbench-minimal";
      }
      {
        assertion = cfg != null && cfg.myconfig.hostContext.system == "x86_64-linux";
        message = "linux_workbench must use x86_64-linux hostContext.system";
      }
      {
        assertion = cfg != null && cfg.myconfig.hostContext.name == "linux_workbench";
        message = "linux_workbench must preserve the stable dotfiles target key";
      }
      {
        assertion = minimalCfg != null && minimalCfg.myconfig.profile.name == "minimal";
        message = "linux_workbench-minimal must select the minimal profile";
      }
      {
        assertion = cfg != null && cfg.myconfig.profile.name == "workbench";
        message = "linux_workbench must select the workbench profile";
      }
      {
        assertion = forbiddenLinuxModuleImports == [ ];
        message = "Linux Home Manager imports Darwin/Homebrew/macOS-only modules: ${lib.concatStringsSep ", " forbiddenLinuxModuleImports}";
      }
      {
        assertion = forbiddenProjectToolchainCatalogEntries == [ ];
        message = "project-pinned toolchains must not have host-global catalog entries: ${lib.concatStringsSep ", " forbiddenProjectToolchainCatalogEntries}";
      }
      {
        assertion = missingLinuxWorkbenchTools == [ ];
        message = "linux_workbench is missing portable workbench tools: ${missingLinuxWorkbenchToolsText}";
      }
      {
        assertion = enabledForbiddenLinuxWorkbenchTools == [ ];
        message = "linux_workbench must not enable forbidden runtime/project tools: ${enabledForbiddenLinuxWorkbenchToolsText}";
      }
    ];
  linuxHomeManagerFailures =
    map (check: check.message) (lib.filter (check: !check.assertion) linuxHomeManagerAssertions);
  linuxHomeManagerFailureText = lib.concatStringsSep "\n" linuxHomeManagerFailures;

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
  vscodeZshLauncher = pkgs.callPackage ../pkgs/dotfiles-vscode-zsh { };
  darwinSystemZsh = pkgs.callPackage ../pkgs/darwin-system-zsh { };
  dotfilesPackage = mkDotfilesPackage {
    inherit pkgs dotfilesCli syncVscodeRust;
  };
  editorSyncAppProgram = mkEditorSyncAppProgram {
    inherit pkgs dotfilesPackage;
  };
  mkEditorSyncApp = {
    type = "app";
    program = "${editorSyncAppProgram}";
    meta.description = "Sync Emacs and Neovim runtime configuration.";
  };
  portableChecks = mkPortableChecks {
    inherit pkgs syncVscodeRust dotfilesPackage editorSyncAppProgram vscodeZshLauncher;
    formatterWrapper = config.treefmt.build.wrapper;
  };
in
{
  treefmt = treefmtConfigFor pkgs;

  formatter = config.treefmt.build.wrapper;

  checks = portableChecks // ({
    treefmt = lib.mkForce portableChecks.treefmt;
    darwinConfigurationsEval =
      let
        _ =
          assert builtins.hasAttr "own_mac" darwinConfigurations;
          assert builtins.hasAttr "work_mac" darwinConfigurations;
          assert builtins.length darwinTargetNames >= 2;
          null;
      in
      builtins.seq _ (pkgs.runCommand "darwin-configurations-eval-check" { } ''
        touch "$out"
      '');

    darwinZshRuntime = pkgs.runCommand "darwin-zsh-runtime-check" { } ''
      if [ ${toString (builtins.length darwinZshRuntimeFailures)} -ne 0 ]; then
        cat >&2 <<'EOF_DARWIN_ZSH_RUNTIME'
      ${darwinZshRuntimeFailureText}
      EOF_DARWIN_ZSH_RUNTIME
        exit 1
      fi
      touch "$out"
    '';

    homebrewShellEnvironment = pkgs.runCommand "homebrew-shell-environment-check" { } ''
      if [ ${toString (builtins.length (lib.flatten homebrewShellEnvironmentFailures))} -ne 0 ]; then
        cat >&2 <<'EOF_HOMEBREW_SHELL_ENVIRONMENT'
      ${homebrewShellEnvironmentFailureText}
      EOF_HOMEBREW_SHELL_ENVIRONMENT
        exit 1
      fi
      touch "$out"
    '';

    homebrewActivation = pkgs.runCommand "homebrew-activation-check" { } ''
      if [ ${toString (builtins.length (lib.flatten homebrewActivationFailures))} -ne 0 ]; then
        cat >&2 <<'EOF_HOMEBREW_ACTIVATION'
      ${homebrewActivationFailureText}
      EOF_HOMEBREW_ACTIVATION
        exit 1
      fi
      touch "$out"
    '';

    linuxHomeManagerEval = pkgs.runCommand "linux-home-manager-eval-check" { } ''
      if [ ${toString (builtins.length linuxHomeManagerFailures)} -ne 0 ]; then
        cat >&2 <<'EOF_LINUX_HOME_MANAGER'
      ${linuxHomeManagerFailureText}
      EOF_LINUX_HOME_MANAGER
        printf 'homeConfigurations targets: %s\n' ${lib.escapeShellArg homeManagerTargetNamesText} >&2
        exit 1
      fi
      touch "$out"
    '';

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

    homeManagerGlobalPkgs = pkgs.runCommand "home-manager-global-pkgs-check" { } ''
      if [ ${toString (builtins.length homeManagerGlobalPkgsFailures)} -ne 0 ]; then
        cat >&2 <<'EOF_HOME_MANAGER_GLOBAL_PKGS'
      ${homeManagerGlobalPkgsFailureText}
      EOF_HOME_MANAGER_GLOBAL_PKGS
        exit 1
      fi
      touch "$out"
    '';

    homebrewNativeCodexPreflight =
      let
        _ =
          assert lib.hasInfix "Codex cask preflight" codexHomebrewNativeActivationText;
          assert lib.hasInfix "dotfiles-stale-" codexHomebrewNativeActivationText;
          assert lib.hasInfix "list --cask codex" codexHomebrewNativeActivationText;
          assert (!lib.hasInfix "Codex cask preflight" nonCodexHomebrewNativeActivationText);
          assert (map homebrewCaskName codexHomebrewNativeModule.config.homebrew.casks) == [ "codex" ];
          assert (map homebrewCaskName codexFilteredHomebrewNativeModule.config.homebrew.casks) == [ ];
          assert (map homebrewCaskName keycluHomebrewNativeModule.config.homebrew.casks) == [ "keyclu" ];
          assert (map homebrewCaskName keycluFilteredHomebrewNativeModule.config.homebrew.casks) == [ ];
          assert (map homebrewCaskName deniedPayloadHomebrewNativeModule.config.homebrew.casks) == [ ];
          assert deniedPayloadHomebrewNativeModule.config.homebrew.brews == [ ];
          null;
      in
      builtins.seq _ (pkgs.runCommand "homebrew-native-codex-preflight-check" { } ''
        touch "$out"
      '');
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    darwinSystemZshSmoke = pkgs.runCommand "darwin-system-zsh-smoke-test"
      {
        nativeBuildInputs = [ pkgs.bash pkgs.coreutils ];
        src = repoPaths.root;
      } ''
      cd "$src"
      export DARWIN_SYSTEM_ZSH="${darwinSystemZsh}/bin/zsh"
      bash scripts/tests/darwin-system-zsh-test.sh
      touch "$out"
    '';
  } // lib.optionalAttrs (pkgs.stdenv.hostPlatform.system == "x86_64-linux" && linuxWorkbenchTarget != null) {
    linuxWorkbenchActivationPackage = linuxWorkbenchTarget.activationPackage;
  });

  devShells.default = mkPortableDevShell {
    inherit pkgs;
    formatterWrapper = config.treefmt.build.wrapper;
  };

  packages = {
    dotfiles = dotfilesPackage;
    dotfiles-cli = dotfilesCli;
    dotfiles-sync-vscode = syncVscodeRust;
    dotfiles-vscode-zsh = vscodeZshLauncher;
    roots = pkgs.callPackage ../pkgs/roots { };
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    darwin-system-zsh = darwinSystemZsh;
    darwin-rebuild = inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild;
  };

  apps = {
    dotfiles = mkDotfilesApp {
      name = "cli";
      description = "Unified dotfiles CLI (apply/agent-notify/update/self-update/doctor/bootstrap/export-clean/gc/list-tools/matrix-tools/sync).";
    };
    sync = mkEditorSyncApp;
    update = mkDotfilesApp {
      name = "update";
      subcommand = "update";
      description = "Update flake inputs, run checks, and build host targets.";
    };
    self-update = mkDotfilesApp {
      name = "self-update";
      subcommand = "self-update";
      description = "Refresh the installed dotfiles CLI and switch the selected Darwin/Home Manager target.";
    };
    agent-notifications-update = mkDotfilesApp {
      name = "agent-notifications-update";
      subcommand = "agent-notify update-runtime";
      description = "Refresh only the coding-agent notification runtime in the default user Nix profile.";
    };
    codex-slack-update = mkDotfilesApp {
      name = "codex-slack-update";
      subcommand = "agent-notify update-runtime";
      description = "Compatibility alias for agent-notifications-update.";
    };
    list-tools = mkDotfilesApp {
      name = "list-tools";
      subcommand = "list-tools";
      description = "List effective myconfig.tools values for a host/profile.";
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
  } // lib.optionalAttrs pkgs.stdenv.isDarwin {
    darwin-rebuild = {
      type = "app";
      program = "${inputs.nix-darwin.packages.${pkgs.stdenv.hostPlatform.system}.darwin-rebuild}/bin/darwin-rebuild";
      meta.description = "Pinned nix-darwin rebuild wrapper from this flake lock.";
    };
  } // {
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
    gc = mkDotfilesApp {
      name = "gc";
      subcommand = "gc";
      description = "Prune repository result GC roots and run Nix garbage collection.";
    };
    format = {
      type = "app";
      program = "${config.treefmt.build.wrapper}/bin/treefmt";
      meta.description = "Format Nix and shell files with treefmt.";
    };
  };
}

{ delib, lib, dotlib, pkgs, inputs, ... }:

# VS Code: isolated instances by purpose with mutable extensions

delib.module {
  name = "tools.editor.vscode";

  options = with delib; moduleOptions {
    enable = boolOption false;
    instances = listOfOption str [ ];
    instancesBase = strOption "";
    appLaunchers = {
      enable = boolOption true;
      targetDir = strOption "Applications/VS Code Instances";
      displayNames = attrsOption { };
    };
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.editor.vscode.enable";
    ifEnabled = { ... }: dotlib.requireUnfree [ "vscode" ];
  };

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      appsDir = ../../../../../apps/vscode;
      defaultSettingsPath = appsDir + "/_default/settings.json";
      defaultExtensionsPath = appsDir + "/_default/extensions.txt";
      defaultExtensionsDisabledPath = appsDir + "/_default/extensions-disabled.txt";
      defaultIconPath = appsDir + "/_default/icon.icns";
      vscodeInstancesScript = "${inputs.self}/nix/scripts/vscode-instances.sh";

      homeDir = myconfig.facts.user.homeDirectory
        or myconfig.constants.homeDirectory
        or "";

      baseDir =
        if cfg.instancesBase != ""
        then cfg.instancesBase
        else "${homeDir}/.local/share/vscode-instances";

      codeBin = "${lib.getBin pkgs.vscode}/bin/code";

      appLaunchersEnabled = cfg.appLaunchers.enable && pkgs.stdenv.isDarwin;
      appLaunchersDir =
        if cfg.appLaunchers.targetDir != ""
        then cfg.appLaunchers.targetDir
        else "Applications/VS Code Instances";

      titleCase = name:
        if name == "" then name else
        let
          len = builtins.stringLength name;
        in
        (lib.toUpper (lib.substring 0 1 name)) + (lib.substring 1 (len - 1) name);

      displayNameFor = name: cfg.appLaunchers.displayNames.${name} or "VSC - ${titleCase name}";

      readJsonOr = path:
        if builtins.pathExists path
        then lib.importJSON path
        else { };

      readExtensionsOr = path:
        if builtins.pathExists path
        then
          let
            content = builtins.readFile path;
            lines = lib.splitString "\n" content;
          in
          lib.filter (line: line != "" && !(lib.hasPrefix "#" line)) lines
        else [ ];

      defaultSettings = readJsonOr defaultSettingsPath;
      defaultExtensions = readExtensionsOr defaultExtensionsPath;
      defaultExtensionsDisabled = readExtensionsOr defaultExtensionsDisabledPath;

      mkAppBundle = name: appDisplayName: appExecName: appLauncherScript: iconPath: iconName:
        let
          bundleId = "com.atalie2m.vscode.${name}";
          launcher = appLauncherScript;
          infoPlist = pkgs.writeText "vscode-${name}-Info.plist" ''
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
              <key>CFBundleName</key>
              <string>${appDisplayName}</string>
              <key>CFBundleDisplayName</key>
              <string>${appDisplayName}</string>
              <key>CFBundleIdentifier</key>
              <string>${bundleId}</string>
              <key>CFBundleExecutable</key>
              <string>${appExecName}</string>
              <key>CFBundlePackageType</key>
              <string>APPL</string>
              ${lib.optionalString (iconName != null) ''
              <key>CFBundleIconFile</key>
              <string>${iconName}</string>
              ''}
            </dict>
            </plist>
          '';
        in
        pkgs.runCommand "vscode-${name}.app" { } ''
          mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
          cp ${launcher} "$out/Contents/MacOS/${appExecName}"
          chmod +x "$out/Contents/MacOS/${appExecName}"
          cp ${infoPlist} "$out/Contents/Info.plist"
          ${lib.optionalString (iconPath != null && iconName != null) ''
          cp ${iconPath} "$out/Contents/Resources/${iconName}.icns"
          ''}
        '';

      autoInstances =
        let
          entries = builtins.readDir appsDir;
          isDir = name: entries.${name} == "directory";
          names = builtins.attrNames entries;
        in
        lib.sort (a: b: a < b) (lib.filter (name: name != "_default" && isDir name) names);

      instanceNames =
        if cfg.instances != [ ]
        then cfg.instances
        else autoInstances;

      mkInstance = name:
        let
          instanceDir = appsDir + "/${name}";
          settingsPath = instanceDir + "/settings.json";
          extensionsPath = instanceDir + "/extensions.txt";
          extensionsDisabledPath = instanceDir + "/extensions-disabled.txt";
          instanceIconPath = instanceDir + "/icon.icns";

          iconPath =
            if builtins.pathExists instanceIconPath then instanceIconPath
            else if builtins.pathExists defaultIconPath then defaultIconPath
            else null;

          iconName =
            if iconPath != null then lib.removeSuffix ".icns" (builtins.baseNameOf (toString iconPath))
            else null;

          appDisplayName = displayNameFor name;
          appExecName = lib.replaceStrings [ "/" ":" ] [ "-" "-" ] appDisplayName;

          instanceSettings = readJsonOr settingsPath;
          instanceExtensions = readExtensionsOr extensionsPath;
          instanceExtensionsDisabled = readExtensionsOr extensionsDisabledPath;
          disabledExtensions = lib.unique (defaultExtensionsDisabled ++ instanceExtensionsDisabled);

          baselineSettings = lib.recursiveUpdate defaultSettings instanceSettings;
          baselineExtensions = lib.unique (defaultExtensions ++ instanceExtensions ++ disabledExtensions);

          settingsJson = pkgs.writeText "vscode-${name}-settings.json" (builtins.toJSON baselineSettings);
          extensionsTxt = pkgs.writeText "vscode-${name}-extensions.txt" (
            lib.concatStringsSep "\n" baselineExtensions + "\n"
          );
          disabledExtensionsTxt = pkgs.writeText "vscode-${name}-extensions-disabled.txt" (
            lib.concatStringsSep "\n" disabledExtensions + "\n"
          );
          baselineId = "${settingsJson}:${extensionsTxt}";
          baselineMarkerId = "${baselineId}:settings-v2";

          commonScriptArgs = [
            "--name"
            name
            "--base-dir"
            baseDir
            "--code-bin"
            codeBin
            "--settings-json"
            settingsJson
            "--extensions-txt"
            extensionsTxt
            "--baseline-id"
            baselineMarkerId
          ];

          bootstrap = pkgs.writeShellApplication {
            name = "code-${name}-bootstrap";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              set -euo pipefail
              exec ${vscodeInstancesScript} bootstrap ${lib.escapeShellArgs commonScriptArgs}
            '';
          };

          launcher = pkgs.writeShellApplication {
            name = "code-${name}";
            text = ''
              set -euo pipefail
              exec ${vscodeInstancesScript} launch ${lib.escapeShellArgs (commonScriptArgs ++ [ "--disabled-extensions-txt" disabledExtensionsTxt ])} -- "$@"
            '';
          };

          appLauncher = pkgs.writeShellScript "code-${name}-app-launcher" ''
            exec "${launcher}/bin/code-${name}" "$@"
          '';

          reset = pkgs.writeShellApplication {
            name = "code-${name}-reset";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              set -euo pipefail
              exec ${vscodeInstancesScript} reset ${lib.escapeShellArgs commonScriptArgs}
            '';
          };

          appBundle =
            if appLaunchersEnabled
            then mkAppBundle name appDisplayName appExecName appLauncher iconPath iconName
            else null;
        in
        {
          inherit name launcher bootstrap reset appBundle appDisplayName;
        };

      instances = map mkInstance instanceNames;
      packagesFor = inst: [ inst.launcher inst.bootstrap inst.reset ];
    in
    {
      programs.vscode = {
        enable = true;
        mutableExtensionsDir = true;
        package = lib.mkDefault pkgs.vscode;
      };

      home.packages =
        lib.concatLists (map packagesFor instances);

      home.file = lib.optionalAttrs appLaunchersEnabled
        (lib.listToAttrs (map
          (inst: {
            name = "vscode-app-${inst.name}";
            value = {
              force = true;
              source = inst.appBundle;
              target = "${appLaunchersDir}/${inst.appDisplayName}.app";
              recursive = true;
            };
          })
          instances));

      home.sessionVariables = {
        VSCODE_INSTANCES_BASE = baseDir;
      };
    };
}

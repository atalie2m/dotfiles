{ delib, lib, pkgs, ... }:

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
    always = { parent, ... }: {
      tools.editor.vscode.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      appsDir = ../../../../../apps/vscode;
      defaultSettingsPath = appsDir + "/_default/settings.json";
      defaultExtensionsPath = appsDir + "/_default/extensions.txt";
      defaultExtensionsDisabledPath = appsDir + "/_default/extensions-disabled.txt";
      defaultIconPath = appsDir + "/_default/icon.icns";

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

          bootstrap = pkgs.writeShellApplication {
            name = "code-${name}-bootstrap";
            runtimeInputs = [ pkgs.jq ];
            text = ''
              set -euo pipefail
              data="${baseDir}/${name}/user-data"
              exts="${baseDir}/${name}/extensions"
              userDir="$data/User"
              marker="$data/.dotfiles-baseline"
              wanted="${baselineMarkerId}"
              mkdir -p "$userDir" "$exts"

              if [ -f "$userDir/settings.json" ]; then
                cp "$userDir/settings.json" "$userDir/settings.json.bak.$(date +%s)"
                tmpdir="''${TMPDIR:-/tmp}"
                tmp="$(mktemp "$tmpdir/vscode-settings.XXXXXX")"
                # Merge baseline + existing settings, but keep instance identity keys (title + bar colors)
                # always controlled by baseline to avoid "seeded value becomes user override" drift.
                jq -s '
                  def force($base; $path):
                    ($base | getpath($path)) as $v
                    | if $v == null then . else setpath($path; $v) end;

                  .[0] as $base | .[1] as $user
                  | ($base * $user)
                  | force($base; ["window.title"])
                  | force($base; ["window.titleSeparator"])
                  | force($base; ["workbench.colorCustomizations","titleBar.activeBackground"])
                  | force($base; ["workbench.colorCustomizations","titleBar.inactiveBackground"])
                  | force($base; ["workbench.colorCustomizations","statusBar.background"])
                  | force($base; ["workbench.colorCustomizations","statusBar.noFolderBackground"])
                ' "${settingsJson}" "$userDir/settings.json" > "$tmp"
                mv "$tmp" "$userDir/settings.json"
              else
                cp "${settingsJson}" "$userDir/settings.json"
              fi

              installed="$("${codeBin}" --user-data-dir "$data" --extensions-dir "$exts" --list-extensions 2>/dev/null || true)"
              force="''${VSCODE_FORCE_EXTENSIONS:-0}"

              while IFS= read -r ext; do
                [ -z "$ext" ] && continue
                case "$ext" in
                  \#*) continue ;;
                esac

                if [ "$force" = "1" ]; then
                  "${codeBin}" --user-data-dir "$data" --extensions-dir "$exts" --install-extension "$ext" --force || true
                  continue
                fi

                if printf '%s\n' "$installed" | grep -Fxq "$ext"; then
                  continue
                fi

                "${codeBin}" --user-data-dir "$data" --extensions-dir "$exts" --install-extension "$ext" || true
              done < "${extensionsTxt}"

              printf "%s" "$wanted" > "$marker"
            '';
          };

          launcher = pkgs.writeShellApplication {
            name = "code-${name}";
            text = ''
              set -euo pipefail
              data="${baseDir}/${name}/user-data"
              exts="${baseDir}/${name}/extensions"
              marker="$data/.dotfiles-baseline"
              wanted="${baselineMarkerId}"
              disable_args=()

              if [ "''${VSCODE_SKIP_BOOTSTRAP:-0}" != "1" ]; then
                if [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$wanted" ]; then
                  "${bootstrap}/bin/code-${name}-bootstrap"
                fi
              fi

              while IFS= read -r ext; do
                [ -z "$ext" ] && continue
                case "$ext" in
                  \#*) continue ;;
                esac
                disable_args+=(--disable-extension "$ext")
              done < "${disabledExtensionsTxt}"

              exec "${codeBin}" \
                --user-data-dir "$data" \
                --extensions-dir "$exts" \
                --new-window \
                "''${disable_args[@]}" \
                "$@"
            '';
          };

          appLauncher = pkgs.writeShellScript "code-${name}-app-launcher" ''
            exec "${launcher}/bin/code-${name}" "$@"
          '';

          reset = pkgs.writeShellApplication {
            name = "code-${name}-reset";
            text = ''
              set -euo pipefail
              base="${baseDir}/${name}"
              if [ -d "$base" ]; then
                ts="$(date +%Y%m%d-%H%M%S)"
                backup="$base.backup-$ts"
                mv "$base" "$backup"
                echo "Backed up $base to $backup"
              fi
              exec "${bootstrap}/bin/code-${name}-bootstrap"
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

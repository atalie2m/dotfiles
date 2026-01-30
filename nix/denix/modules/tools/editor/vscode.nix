{ delib, lib, pkgs, ... }:

# VS Code: isolated instances by purpose with mutable extensions
delib.module {
  name = "tools.editor.vscode";

  options = with delib; moduleOptions {
    enable = boolOption false;
    instances = listOfOption str [];
    instancesBase = strOption "";
    appLaunchers = {
      enable = boolOption true;
      targetDir = strOption "Applications/VS Code Instances";
      displayNames = attrsOption {};
      dynamicNames = {
        enable = boolOption false;
        prefix = strOption "VSC - ";
        profileIds = attrsOption {};
        baseDir = strOption ".base";
      };
    };
  };

  myconfig = {
    always = { parent, ... }: {
      tools.editor.vscode.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, myconfig, ... }: let
    appsDir = ../../../../../apps/vscode;
    defaultSettingsPath = appsDir + "/_default/settings.json";
    defaultExtensionsPath = appsDir + "/_default/extensions.txt";

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
    appLaunchersBaseDir =
      if cfg.appLaunchers.dynamicNames.enable
      then "${appLaunchersDir}/${cfg.appLaunchers.dynamicNames.baseDir}"
      else appLaunchersDir;

    titleCase = name:
      if name == "" then name else
        let
          len = builtins.stringLength name;
        in
          (lib.toUpper (lib.substring 0 1 name)) + (lib.substring 1 (len - 1) name);

    displayNameFor = name: cfg.appLaunchers.displayNames.${name} or "VSC - ${titleCase name}";
    profileIdFor = name: cfg.appLaunchers.dynamicNames.profileIds.${name} or name;

    readJsonOr = path:
      if builtins.pathExists path
      then lib.importJSON path
      else {};

    readExtensionsOr = path:
      if builtins.pathExists path
      then
        let
          content = builtins.readFile path;
          lines = lib.splitString "\n" content;
        in
          lib.filter (line: line != "" && !(lib.hasPrefix "#" line)) lines
      else [];

    defaultSettings = readJsonOr defaultSettingsPath;
    defaultExtensions = readExtensionsOr defaultExtensionsPath;

    mkAppBundle = name: appDisplayName: let
      bundleId = "com.atalie2m.vscode.${name}";
      launcher = pkgs.writeShellScript "code-${name}-app" ''
        exec "${codeBin}" \
          --user-data-dir "${baseDir}/${name}/user-data" \
          --extensions-dir "${baseDir}/${name}/extensions" \
          --new-window \
          "$@"
      '';
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
          <string>launcher</string>
          <key>CFBundlePackageType</key>
          <string>APPL</string>
        </dict>
        </plist>
      '';
    in pkgs.runCommand "vscode-${name}.app" {} ''
      mkdir -p "$out/Contents/MacOS" "$out/Contents/Resources"
      cp ${launcher} "$out/Contents/MacOS/launcher"
      chmod +x "$out/Contents/MacOS/launcher"
      cp ${infoPlist} "$out/Contents/Info.plist"
    '';

    autoInstances =
      let
        entries = builtins.readDir appsDir;
        isDir = name: entries.${name} == "directory";
        names = builtins.attrNames entries;
      in
        lib.sort (a: b: a < b) (lib.filter (name: name != "_default" && isDir name) names);

    instanceNames =
      if cfg.instances != []
      then cfg.instances
      else autoInstances;

    mkInstance = name: let
      instanceDir = appsDir + "/${name}";
      settingsPath = instanceDir + "/settings.json";
      extensionsPath = instanceDir + "/extensions.txt";
      appDisplayName = displayNameFor name;

      instanceSettings = readJsonOr settingsPath;
      instanceExtensions = readExtensionsOr extensionsPath;

      baselineSettings = lib.recursiveUpdate defaultSettings instanceSettings;
      baselineExtensions = lib.unique (defaultExtensions ++ instanceExtensions);

      settingsJson = pkgs.writeText "vscode-${name}-settings.json" (builtins.toJSON baselineSettings);
      extensionsTxt = pkgs.writeText "vscode-${name}-extensions.txt" (
        lib.concatStringsSep "\n" baselineExtensions + "\n"
      );

      launcher = pkgs.writeShellApplication {
        name = "code-${name}";
        text = ''
          exec "${codeBin}" \
            --user-data-dir "${baseDir}/${name}/user-data" \
            --extensions-dir "${baseDir}/${name}/extensions" \
            --new-window \
            "$@"
        '';
      };

      bootstrap = pkgs.writeShellApplication {
        name = "code-${name}-bootstrap";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          set -euo pipefail
          data="${baseDir}/${name}/user-data"
          exts="${baseDir}/${name}/extensions"
          userDir="$data/User"
          mkdir -p "$userDir" "$exts"

          if [ -f "$userDir/settings.json" ]; then
            cp "$userDir/settings.json" "$userDir/settings.json.bak.$(date +%s)"
            tmp="$(mktemp "${TMPDIR:-/tmp}/vscode-settings.XXXXXX")"
            jq -s '.[0] * .[1]' "${settingsJson}" "$userDir/settings.json" > "$tmp"
            mv "$tmp" "$userDir/settings.json"
          else
            cp "${settingsJson}" "$userDir/settings.json"
          fi

          while IFS= read -r ext; do
            [ -z "$ext" ] && continue
            case "$ext" in
              \#*) continue ;;
            esac
            "${codeBin}" --user-data-dir "$data" --extensions-dir "$exts" --install-extension "$ext" --force || true
          done < "${extensionsTxt}"
        '';
      };

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
      appBundle = if appLaunchersEnabled then mkAppBundle name appDisplayName else null;
    in {
      inherit name launcher bootstrap reset appBundle appDisplayName;
    };

    instances = map mkInstance instanceNames;
    packagesFor = inst: [ inst.launcher inst.bootstrap inst.reset ];
  in {
    programs.vscode = {
      enable = true;
      mutableExtensionsDir = true;
      package = lib.mkDefault pkgs.vscode;
    };

    home.packages =
      lib.concatLists (map packagesFor instances)
      ++ lib.optionals cfg.appLaunchers.dynamicNames.enable [ pkgs.jq ];

    home.file = lib.optionalAttrs appLaunchersEnabled
      (lib.listToAttrs (map (inst: {
        name = "vscode-app-${inst.name}";
        value = {
          source = inst.appBundle;
          target = "${appLaunchersBaseDir}/${inst.appDisplayName}.app";
          recursive = true;
        };
      }) instances));

    home.activation.vscodeAppLauncherNames =
      lib.mkIf (appLaunchersEnabled && cfg.appLaunchers.dynamicNames.enable) (lib.mkOrder 210 ''
        base_dir="${appLaunchersBaseDir}"
        target_dir="${appLaunchersDir}"
        prefix="${cfg.appLaunchers.dynamicNames.prefix}"

        mkdir -p "$target_dir"

        ${lib.concatMapStringsSep "\n" (inst: ''
          base_app="$base_dir/${inst.appDisplayName}.app"
          if [ -d "$base_app" ]; then
            profile_id="${profileIdFor inst.name}"
            storage_json="${baseDir}/${inst.name}/user-data/User/globalStorage/storage.json"
            label=""

            if [ -f "$storage_json" ]; then
              label="$(jq -r --arg id "$profile_id" '
                first( .. | objects
                  | select(has(\"id\") and .id == (\"workbench.profiles.actions.profileEntry.\" + $id))
                  | .label
                ) // empty
              ' "$storage_json" 2>/dev/null || true)"
            fi

            if [ -z "$label" ]; then
              if [ "$profile_id" = "__default__profile__" ]; then
                label="Default"
              else
                label="$profile_id"
              fi
            fi

            safe_label="''${label//\\//-}"
            safe_label="''${safe_label//:/-}"
            dest="$target_dir/''${prefix}''${safe_label}.app"

            find "$target_dir" -maxdepth 1 -type l -name "''${prefix}*.app" -lname "$base_app" -exec rm -f {} + || true
            if [ ! -e "$dest" ] || [ -L "$dest" ]; then
              ln -sfn "$base_app" "$dest"
            fi
          fi
        '') instances}
      '');

    home.sessionVariables = {
      VSCODE_INSTANCES_BASE = baseDir;
    };
  };
}

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
      profiledApp = {
        enable = boolOption false;
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
    defaultIconPath = appsDir + "/_default/icon.icns";
    defaultMetaPath = appsDir + "/_default/meta.json";

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
    appLaunchersDirAbs =
      if lib.hasPrefix "/" appLaunchersDir
      then appLaunchersDir
      else "${homeDir}/${appLaunchersDir}";
    appLaunchersBaseDirAbs =
      if lib.hasPrefix "/" appLaunchersBaseDir
      then appLaunchersBaseDir
      else "${homeDir}/${appLaunchersBaseDir}";

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

    mkAppBundle = name: appDisplayName: appExecName: appLauncherScript: iconPath: iconName: let
      bundleId = "com.atalie2m.vscode.${name}";
      launcher = appLauncherScript;
      iconNameStr = if iconName != null then iconName else "";
      baseApp = "${pkgs.vscode}/Applications/Visual Studio Code.app";
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
      if cfg.appLaunchers.profiledApp.enable
      then pkgs.runCommand "vscode-${name}.app" { nativeBuildInputs = [ pkgs.python3 ]; } ''
        mkdir -p "$out"
        cp -R "${baseApp}/Contents" "$out/Contents"
        chmod -R u+w "$out/Contents"
        cp ${launcher} "$out/Contents/MacOS/${appExecName}"
        chmod +x "$out/Contents/MacOS/${appExecName}"

        python3 - <<'PY'
        import os
        import plistlib
        from pathlib import Path

        out = Path(os.environ["out"])
        info = out / "Contents" / "Info.plist"
        with info.open("rb") as f:
          data = plistlib.load(f)

        old_name = data.get("CFBundleName") or data.get("CFBundleDisplayName") or "Code"
        new_name = "${appExecName}"

        data["CFBundleName"] = new_name
        data["CFBundleDisplayName"] = new_name
        data["CFBundleIdentifier"] = "${bundleId}"
        data["CFBundleExecutable"] = "${appExecName}"
        if "${iconNameStr}":
          data["CFBundleIconFile"] = "${iconNameStr}"

        with info.open("wb") as f:
          plistlib.dump(data, f)

        # Rename helper apps to match the new bundle name so Electron can find them.
        frameworks = out / "Contents" / "Frameworks"
        if frameworks.exists():
          suffixes = ["Helper", "Helper (GPU)", "Helper (Plugin)", "Helper (Renderer)"]
          for suffix in suffixes:
            want = f"{new_name} {suffix}.app"
            candidates = [p for p in frameworks.iterdir() if p.name.endswith(f" {suffix}.app")]
            old_app = frameworks / f"{old_name} {suffix}.app"
            new_app = frameworks / want

            if new_app.exists():
              target_app = new_app
            elif old_app.exists():
              target_app = old_app
            elif candidates:
              target_app = candidates[0]
            else:
              continue

            if target_app != new_app:
              target_app.rename(new_app)

            helper_info = new_app / "Contents" / "Info.plist"
            if helper_info.exists():
              with helper_info.open("rb") as f:
                hdata = plistlib.load(f)

              helper_name = f"{new_name} {suffix}"
              hdata["CFBundleName"] = helper_name
              hdata["CFBundleDisplayName"] = helper_name

              helper_id = "${bundleId}.helper"
              if suffix != "Helper":
                extra = suffix.replace("Helper", "").strip()
                extra = extra.strip("() ").lower()
                if extra:
                  helper_id = f"{helper_id}.{extra}"
              hdata["CFBundleIdentifier"] = helper_id

              old_exec = hdata.get("CFBundleExecutable")
              macos = new_app / "Contents" / "MacOS"
              old_exec_path = None
              if old_exec:
                cand = macos / old_exec
                if cand.exists():
                  old_exec_path = cand
              if old_exec_path is None and macos.exists():
                files = [p for p in macos.iterdir() if p.is_file() and not p.name.startswith(".")]
                if len(files) == 1:
                  old_exec_path = files[0]
                elif files:
                  prefer = [p for p in files if "Helper" in p.name]
                  old_exec_path = prefer[0] if prefer else files[0]

              new_exec = helper_name
              new_exec_path = macos / new_exec
              if old_exec_path is not None and old_exec_path.exists() and old_exec_path != new_exec_path:
                old_exec_path.rename(new_exec_path)
              hdata["CFBundleExecutable"] = new_exec

              with helper_info.open("wb") as f:
                plistlib.dump(hdata, f)
        PY

        ${lib.optionalString (iconPath != null && iconName != null) ''
        cp ${iconPath} "$out/Contents/Resources/${iconName}.icns"
        ''}

        rm -rf "$out/Contents/_CodeSignature" "$out/Contents/CodeResources"
      ''
      else pkgs.runCommand "vscode-${name}.app" {} ''
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
      if cfg.instances != []
      then cfg.instances
      else autoInstances;

    mkInstance = name: let
      instanceDir = appsDir + "/${name}";
      settingsPath = instanceDir + "/settings.json";
      extensionsPath = instanceDir + "/extensions.txt";
      instanceIconPath = instanceDir + "/icon.icns";
      instanceMetaPath = instanceDir + "/meta.json";

      defaultMeta = readJsonOr defaultMetaPath;
      instanceMeta = readJsonOr instanceMetaPath;

      metaDisplayName =
        if instanceMeta ? displayName then instanceMeta.displayName
        else if defaultMeta ? displayName then defaultMeta.displayName
        else null;

      metaIconName =
        if instanceMeta ? iconName then instanceMeta.iconName
        else if defaultMeta ? iconName then defaultMeta.iconName
        else null;

      instanceMetaIcon =
        if instanceMeta ? icon then instanceMeta.icon
        else null;

      defaultMetaIcon =
        if defaultMeta ? icon then defaultMeta.icon
        else null;

      metaIconPath =
        if instanceMetaIcon != null && instanceMetaIcon != "" then instanceDir + "/${instanceMetaIcon}"
        else if defaultMetaIcon != null && defaultMetaIcon != "" then appsDir + "/_default/${defaultMetaIcon}"
        else null;

      iconPath =
        if metaIconPath != null && builtins.pathExists metaIconPath then metaIconPath
        else if builtins.pathExists instanceIconPath then instanceIconPath
        else if builtins.pathExists defaultIconPath then defaultIconPath
        else null;

      iconName =
        if metaIconName != null && metaIconName != "" then lib.removeSuffix ".icns" metaIconName
        else if iconPath != null then lib.removeSuffix ".icns" (builtins.baseNameOf (toString iconPath))
        else null;

      appDisplayName =
        if lib.hasAttr name cfg.appLaunchers.displayNames
        then displayNameFor name
        else if metaDisplayName != null && metaDisplayName != ""
        then metaDisplayName
        else displayNameFor name;
      appExecName = lib.replaceStrings [ "/" ":" ] [ "-" "-" ] appDisplayName;

      appBundlePath = "${appLaunchersBaseDirAbs}/${appDisplayName}.app";

      instanceSettings = readJsonOr settingsPath;
      instanceExtensions = readExtensionsOr extensionsPath;

      baselineSettings = lib.recursiveUpdate defaultSettings instanceSettings;
      baselineExtensions = lib.unique (defaultExtensions ++ instanceExtensions);

      settingsJson = pkgs.writeText "vscode-${name}-settings.json" (builtins.toJSON baselineSettings);
      extensionsTxt = pkgs.writeText "vscode-${name}-extensions.txt" (
        lib.concatStringsSep "\n" baselineExtensions + "\n"
      );
      baselineId = "${settingsJson}:${extensionsTxt}";

      bootstrap = pkgs.writeShellApplication {
        name = "code-${name}-bootstrap";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          set -euo pipefail
          data="${baseDir}/${name}/user-data"
          exts="${baseDir}/${name}/extensions"
          userDir="$data/User"
          marker="$data/.dotfiles-baseline"
          wanted="${baselineId}"
          mkdir -p "$userDir" "$exts"

          if [ -f "$userDir/settings.json" ]; then
            cp "$userDir/settings.json" "$userDir/settings.json.bak.$(date +%s)"
            tmpdir="''${TMPDIR:-/tmp}"
            tmp="$(mktemp "$tmpdir/vscode-settings.XXXXXX")"
            jq -s '.[0] * .[1]' "${settingsJson}" "$userDir/settings.json" > "$tmp"
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
          wanted="${baselineId}"

          if [ "''${VSCODE_SKIP_BOOTSTRAP:-0}" != "1" ]; then
            if [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$wanted" ]; then
              "${bootstrap}/bin/code-${name}-bootstrap"
            fi
          fi

          ${lib.optionalString cfg.appLaunchers.profiledApp.enable ''
          app_path="${appBundlePath}"
          if [ -d "$app_path" ]; then
            use_cli=0
            for arg in "$@"; do
              case "$arg" in
                -*) use_cli=1 ;;
              esac
            done

            if [ "$use_cli" = "0" ]; then
              app_launcher="$app_path/Contents/MacOS/${appExecName}"
              if [ -x "$app_launcher" ]; then
                exec "$app_launcher" "$@"
              fi
            fi
          fi
          ''}

          exec "${codeBin}" \
            --user-data-dir "$data" \
            --extensions-dir "$exts" \
            --new-window \
            "$@"
        '';
      };

      appLauncher = pkgs.writeShellScript "code-${name}-app-launcher" (
        if cfg.appLaunchers.profiledApp.enable then ''
          set -euo pipefail
          data="${baseDir}/${name}/user-data"
          exts="${baseDir}/${name}/extensions"
          marker="$data/.dotfiles-baseline"
          wanted="${baselineId}"

          if [ "''${VSCODE_SKIP_BOOTSTRAP:-0}" != "1" ]; then
            if [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$wanted" ]; then
              "${bootstrap}/bin/code-${name}-bootstrap"
            fi
          fi

          appdir="$(cd "$(dirname "$0")/.." && pwd)"
          bin=""
          if [ -x "$appdir/MacOS/Electron" ]; then
            bin="$appdir/MacOS/Electron"
          elif [ -x "$appdir/MacOS/Visual Studio Code" ]; then
            bin="$appdir/MacOS/Visual Studio Code"
          elif [ -x "$appdir/MacOS/Code" ]; then
            bin="$appdir/MacOS/Code"
          fi

          if [ -z "$bin" ]; then
            echo "VS Code binary not found in app bundle." >&2
            exit 1
          fi

          exec "$bin" \
            --user-data-dir "$data" \
            --extensions-dir "$exts" \
            --new-window \
            "$@"
        '' else ''
          exec "${launcher}/bin/code-${name}" "$@"
        ''
      );

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

    home.file = lib.optionalAttrs (appLaunchersEnabled && !cfg.appLaunchers.profiledApp.enable)
      (lib.listToAttrs (map (inst: {
        name = "vscode-app-${inst.name}";
        value = {
          source = inst.appBundle;
          target = "${appLaunchersBaseDir}/${inst.appDisplayName}.app";
          recursive = true;
        };
      }) instances));

    home.activation.vscodeAppBundles =
      lib.mkIf (appLaunchersEnabled && cfg.appLaunchers.profiledApp.enable) (lib.mkOrder 200 ''
        base_dir="${appLaunchersBaseDirAbs}"
        mkdir -p "$base_dir"

        ${lib.concatMapStringsSep "\n" (inst: ''
          src="${inst.appBundle}"
          dest="$base_dir/${inst.appDisplayName}.app"
          marker="$base_dir/.dotfiles-source-${inst.name}"

          if [ ! -d "$dest" ] || [ ! -f "$marker" ] || [ "$(cat "$marker" 2>/dev/null || true)" != "$src" ]; then
            rm -rf "$dest"
            cp -R "$src" "$dest"
            chmod -R u+w "$dest"
            rm -f "$dest/.dotfiles-source" "$dest/Contents/.dotfiles-source"
            rm -rf "$dest/Contents/_CodeSignature" "$dest/Contents/CodeResources"
            if /usr/bin/codesign --force --deep --sign - --timestamp=none "$dest"; then
              printf "%s" "$src" > "$marker"
            else
              echo "codesign failed for $dest" >&2
              rm -f "$marker"
            fi
          fi
        '') instances}
      '');

    home.activation.vscodeAppLauncherNames =
      lib.mkIf (appLaunchersEnabled && cfg.appLaunchers.dynamicNames.enable) (lib.mkOrder 210 ''
        base_dir="${appLaunchersBaseDirAbs}"
        target_dir="${appLaunchersDirAbs}"
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

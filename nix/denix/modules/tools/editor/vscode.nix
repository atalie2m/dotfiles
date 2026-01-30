{ delib, lib, pkgs, ... }:

# VS Code: isolated instances by purpose with mutable extensions
delib.module {
  name = "tools.editor.vscode";

  options = with delib; moduleOptions {
    enable = boolOption false;
    instances = listOfOption str [];
    instancesBase = strOption "";
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
    in {
      inherit launcher bootstrap reset;
    };

    instances = map mkInstance instanceNames;
    packagesFor = inst: [ inst.launcher inst.bootstrap inst.reset ];
  in {
    programs.vscode = {
      enable = true;
      mutableExtensionsDir = true;
      package = lib.mkDefault pkgs.vscode;
    };

    home.packages = lib.concatLists (map packagesFor instances);

    home.sessionVariables = {
      VSCODE_INSTANCES_BASE = baseDir;
    };
  };
}

{ dotmod, config, lib, pkgs, repoPaths, ... }:

(dotmod.mkModule { inherit config; }) {
  path = "tools.system.karabiner";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
  };

  darwinOnEnable = { myconfig, ... }:
    let
      ruleDir = repoPaths.keyboards + "/karabiner/complex_modifications";
      keyboardType =
        let
          configured = myconfig.hostContext.machine.keyboardType or null;
        in
        if configured == null then "ansi" else configured;

      #
      # 1. Curated rule bundles (source of truth)
      #
      ruleFiles = {
        standard = ruleDir + "/curated-standard.json";
        a2m = ruleDir + "/curated-a2m.json";
      };

      #
      # 2. Import curated rules
      #
      allRulesFrom = path: (lib.importJSON path).rules;

      #
      # 3. Build rule sets for each profile from curated bundles
      #
      standardRules = allRulesFrom ruleFiles.standard;
      ataliesRules = allRulesFrom ruleFiles.a2m;

      #
      # 4. Build Home Manager module for Karabiner
      #
      mkKarabinerHomeModule = { ... }:
        let
          # 4. Full Karabiner config
          #
          # Build karabiner.json in the store and link it into place
          karabinerJson = pkgs.writeText "karabiner.json" (builtins.toJSON {
            global = {
              check_for_updates_on_startup = false;
              show_in_menu_bar = true;
            };

            profiles = [
              {
                name = "A2m";
                selected = false;
                complex_modifications.rules = ataliesRules;
                virtual_hid_keyboard = {
                  keyboard_type_v2 = keyboardType;
                };
              }
              {
                name = "Std";
                selected = true;
                complex_modifications.rules = standardRules;
                virtual_hid_keyboard = {
                  keyboard_type_v2 = keyboardType;
                };
              }
            ];
          });

          #
          # 5. Symlink the entire modifications directory
          #
          complexModsSymlink = {
            force = true;
            source = ruleDir;
            recursive = true; # keep file names intact
          };
        in
        {
          # Link Karabiner settings without installing the application.
          xdg.configFile."karabiner/karabiner.json" = {
            source = karabinerJson;
            force = true;
          };
          xdg.configFile."karabiner/assets/complex_modifications" = complexModsSymlink;
        };
    in
    {
      home-manager.sharedModules = [ mkKarabinerHomeModule ];
    };
}

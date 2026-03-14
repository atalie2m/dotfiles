{ delib, lib, dotlib, repoPaths, ... }:

delib.module {
  name = "tools.system.karabiner";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.system.karabiner.enable";
  };

  darwin.ifEnabled = { ... }:
    let
      ruleDir = repoPaths.keyboards + "/karabiner/complex_modifications";

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
      mkKarabinerHomeModule = { pkgs, ... }:
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
                  keyboard_type_v2 = "ansi";
                };
              }
              {
                name = "Std";
                selected = true;
                complex_modifications.rules = standardRules;
                virtual_hid_keyboard = {
                  keyboard_type_v2 = "ansi";
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
          # Install everything (symlink karabiner.json and complex_modifications).
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

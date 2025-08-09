{ delib, lib, pkgs, ... }:

delib.module {
  name = "karabiner";

  options.karabiner = with delib.options; {
    enable = boolOption false;
  };

  home.ifEnabled = { cfg, ... }: let
    # Path to the root of your dotfiles repo
    dotfilesRoot = ../../../.;

    #
    # 1. Complex-modification rule files
    #
    ruleDir = "${dotfilesRoot}/keyboards/karabiner/complex_modifications";

    # List every JSON file you care about once; easier to reorder / comment out
    ruleFiles = {
      japaneseToggle = "${ruleDir}/japanese-input-toggle.json";  
      spaceShift     = "${ruleDir}/spacebar-to-shift.json";  
      vyletAlt       = "${ruleDir}/vylet-alt-layout.json";  
      shingetaEn     = "${ruleDir}/shingeta/shingeta_en.json";  
      shingetaJp     = "${ruleDir}/shingeta/shingeta_jp.json";  
    };

    #
    # 2. Helper functions to selectively import rules
    #
    # Import all rules from a file
    allRulesFrom = path: (lib.importJSON path).rules;

    # Import only specific rules by description from a file
    specificRulesFrom = path: descriptions:
      lib.filter (rule: lib.elem (rule.description or "") descriptions)
                 (allRulesFrom path);

    #
    # 3. Build rule sets for each profile by selective import
    #
    # Standard profile: import only specific rules from specific files
    standardRules = lib.concatLists [
      (specificRulesFrom ruleFiles.japaneseToggle [
        "コマンドキーを単体で押したときに、英数・かなキーを送信する。（左コマンドキーは英数、右コマンドキーはかな） (rev 3)"
      ])
      (allRulesFrom ruleFiles.spaceShift)  # Import all rules from spacebar-to-shift
    ];

    # Atalie's profile: import specific rules from japanese-input-toggle, all from others
    ataliesRules = lib.concatLists [
      (specificRulesFrom ruleFiles.japaneseToggle [
        "コマンドキーを単体で押したときに、英数・かなキーを送信する。（左コマンドキーは英数、右コマンドキーはかな） (rev 3)"
      ])
      (allRulesFrom ruleFiles.spaceShift)   # All predefined
      (allRulesFrom ruleFiles.vyletAlt)     # All predefined
      (allRulesFrom ruleFiles.shingetaJp)   # All predefined (excluding shingetaEn)
    ];

    #
    # 4. Full Karabiner config
    #
    karabinerJson = pkgs.writeText "karabiner.json" (builtins.toJSON {
      global = {
        check_for_updates_on_startup = false;
        show_in_menu_bar             = true;
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
      source = ruleDir;
      recursive = true;    # keep file names intact
    };

  in {
    # Install everything
    xdg.configFile."karabiner/karabiner.json".source = karabinerJson;
    xdg.configFile."karabiner/assets/complex_modifications" = complexModsSymlink;

    #
    # Optional: write a small debug text next to the config
    #
    home.file.".karabiner-debug.txt".text = ''
      Karabiner-Elements Nix module diagnostics

      dotfilesRoot:  ${dotfilesRoot}

      Rule files considered:
      ${lib.concatMapStringsSep "\n" (name: "  • " + ruleFiles.${name}) (builtins.attrNames ruleFiles)}
    '';
  };
}

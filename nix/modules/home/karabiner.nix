{ config, lib, pkgs, ... }:

let
  # Use relative path from the current file location instead of absolute path
  dotfilesRoot = ../../../.;  # Go up to the dotfiles root from nix/modules/home/
  
  # Karabiner-Elements configuration files list
  karabinerConfigs = [
    {
      name = "japanese-input-toggle.json";
      source = dotfilesRoot + "/keyboards/karabiner/complex_modifications/japanese-input-toggle.json";
      description = "Japanese input method switching configurations";
    }
    {
      name = "spacebar-to-shift.json";
      source = dotfilesRoot + "/keyboards/karabiner/complex_modifications/spacebar-to-shift.json";
      description = "Space-and-Shift (SandS) functionality";
    }
    {
      name = "vylet-alt-layout.json";
      source = dotfilesRoot + "/keyboards/karabiner/complex_modifications/vylet-alt-layout.json";
      description = "Vylet alternative keyboard layout";
    }
    {
      name = "shingeta_en.json";
      source = dotfilesRoot + "/keyboards/karabiner/complex_modifications/shingeta/shingeta_en.json";
      description = "Shingeta layout for English typing games";
    }
    {
      name = "shingeta_jp.json";
      source = dotfilesRoot + "/keyboards/karabiner/complex_modifications/shingeta/shingeta_jp.json";
      description = "Shingeta layout for Japanese input";
    }
  ];

  # Filter existing files and create debug information
  existingConfigs = builtins.filter (config: builtins.pathExists config.source) karabinerConfigs;
  missingConfigs = builtins.filter (config: !(builtins.pathExists config.source)) karabinerConfigs;

  # Helper function to create symbolic links
  mkKarabinerLinks = configs: lib.listToAttrs (map (config: {
    name = ".config/karabiner/assets/complex_modifications/${config.name}";
    value = {
      source = config.source;
    };
  }) configs);

  # Debug information
  debugInfo = ''
    Karabiner-Elements Configuration Debug Information:
    
    Dotfiles Root Path: ${toString dotfilesRoot}
    
    Existing files (${toString (builtins.length existingConfigs)}):
    ${lib.concatMapStringsSep "\n" (config: "  ✓ ${config.name} -> ${toString config.source}") existingConfigs}
    
    Missing files (${toString (builtins.length missingConfigs)}):
    ${lib.concatMapStringsSep "\n" (config: "  ✗ ${config.name} -> ${toString config.source}") missingConfigs}
    
    Total configurations: ${toString (builtins.length karabinerConfigs)}
    Successfully linked: ${toString (builtins.length existingConfigs)}
  '';

in
# Output debug information
lib.trace debugInfo
{
  # Create symbolic links for Karabiner-Elements configuration files
  home.file = (mkKarabinerLinks existingConfigs) // {
    # Also create a debug file in the home directory
    ".karabiner-debug.txt" = {
      text = debugInfo;
    };
  };
}

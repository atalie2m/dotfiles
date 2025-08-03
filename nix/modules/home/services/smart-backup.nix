{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.smartBackup;
in
{
  options.services.smartBackup = {
    enable = mkEnableOption "Smart backup service with timestamped backups";

    files = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of files to backup with smart timestamping";
      example = [
        "$HOME/Library/Preferences/com.apple.Terminal.plist"
        "$HOME/.config/some-config.json"
      ];
    };

    managedFiles = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of files to backup and remove (for Home Manager managed files)";
      example = [
        "$HOME/.config/karabiner/karabiner.json"
      ];
    };

    backupSuffix = mkOption {
      type = types.str;
      default = "backup";
      description = "Suffix for backup files";
    };

    timestampFormat = mkOption {
      type = types.str;
      default = "%Y%m%d-%H%M%S";
      description = "Format for timestamp in backup filenames";
    };
  };

  config = mkIf cfg.enable {
    home.activation.smartBackup = config.lib.dag.entryBefore ["checkLinkTargets"] ''
      # Smart backup function with configurable options
      smart_backup() {
        local original_file="$1"
        local backup_suffix="${cfg.backupSuffix}"
        local timestamp_format="${cfg.timestampFormat}"
        local backup_base="$original_file.$backup_suffix"

        if [[ -f "$original_file" ]]; then
          if [[ -f "$backup_base" ]]; then
            # Move existing backup with timestamp
            local timestamp=$(date +"$timestamp_format")
            local timestamped_backup="$backup_base-$timestamp"
            echo "Moving existing backup $backup_base to $timestamped_backup"
            mv "$backup_base" "$timestamped_backup"
          fi
          echo "Backing up $original_file to $backup_base"
          cp "$original_file" "$backup_base"
        fi
      }

      # Smart backup function for managed files (backup and remove)
      smart_backup_managed() {
        local original_file="$1"
        local backup_suffix="${cfg.backupSuffix}"
        local timestamp_format="${cfg.timestampFormat}"
        local backup_base="$original_file.$backup_suffix"

        if [[ -f "$original_file" ]]; then
          if [[ -f "$backup_base" ]]; then
            # Move existing backup with timestamp
            local timestamp=$(date +"$timestamp_format")
            local timestamped_backup="$backup_base-$timestamp"
            echo "Moving existing backup $backup_base to $timestamped_backup"
            mv "$backup_base" "$timestamped_backup"
          fi
          echo "Backing up and removing $original_file to $backup_base"
          mv "$original_file" "$backup_base"
        fi
      }

      # Backup all configured files
      ${concatMapStringsSep "\n" (file: ''
        smart_backup "${file}"
      '') cfg.files}

      # Backup and remove all managed files
      ${concatMapStringsSep "\n" (file: ''
        smart_backup_managed "${file}"
      '') cfg.managedFiles}
    '';
  };
}

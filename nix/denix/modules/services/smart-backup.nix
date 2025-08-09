{ delib, lib, ... }:

delib.module {
  name = "smartBackup";

  options.smartBackup = with delib.options; {
    enable = boolOption false;
    files = listOfOption str [];
    managedFiles = listOfOption str [
      "$HOME/.config/karabiner/karabiner.json"
    ];
    backupSuffix = strOption "backup";
    timestampFormat = strOption "%Y%m%d-%H%M%S";
  };

  home.ifEnabled = { cfg, ... }: {
    home.activation.smartBackup = lib.mkOrder 50 ''
      echo "Smart Backup: Starting backup process..."

      # Smart backup function with configurable options
      smart_backup() {
        local original_file="$1"
        local backup_suffix="${cfg.backupSuffix}"
        local timestamp_format="${cfg.timestampFormat}"
        local backup_base="$original_file.$backup_suffix"

        if [[ -f "$original_file" ]]; then
          if [[ -f "$backup_base" ]]; then
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
      ${lib.concatMapStringsSep "\n" (file: ''
        expanded_file=$(eval echo "${file}")
        smart_backup "$expanded_file"
      '') cfg.files}

      # Backup and remove all managed files
      ${lib.concatMapStringsSep "\n" (file: ''
        expanded_file=$(eval echo "${file}")
        smart_backup_managed "$expanded_file"
      '') cfg.managedFiles}

      echo "Smart Backup: Backup process completed."
    '';
  };
}

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

  # Enable Home Manager's built-in backup of conflicting files.
  # Use a distinct extension to avoid clobbering our own backups (".backup").
  darwin.ifEnabled = { cfg, ... }: {
    home-manager.backupFileExtension = "${cfg.backupSuffix}-hm";
  };

  home.ifEnabled = { cfg, ... }: {
    # Run BEFORE Home Manager's linkGeneration to avoid backup clobber errors.
    home.activation.smartBackup = lib.hm.dag.entryBefore [ "linkGeneration" ] ''
      echo "Smart Backup: Starting backup process..."

      # Rotate an existing Home Manager backup (e.g. *.backup-hm) to a timestamped name
      rotate_hm_backup() {
        local original_file="$1"
        local backup_suffix="${cfg.backupSuffix}"
        local timestamp_format="${cfg.timestampFormat}"
        local hm_backup_file="$original_file.${cfg.backupSuffix}-hm"

        if [[ -e "$hm_backup_file" ]]; then
          local timestamp=$(date +"$timestamp_format")
          local timestamped_backup="$hm_backup_file-$timestamp"
          echo "Rotating existing HM backup $hm_backup_file to $timestamped_backup"
          mv "$hm_backup_file" "$timestamped_backup"
        fi
      }

      # Smart backup function with configurable options (keeps original)
      smart_backup() {
        local original_file="$1"
        local backup_suffix="${cfg.backupSuffix}"
        local timestamp_format="${cfg.timestampFormat}"
        local backup_base="$original_file.$backup_suffix"

        if [[ -f "$original_file" || -d "$original_file" ]]; then
          local timestamp=$(date +"$timestamp_format")
          local timestamped_backup="$backup_base-$timestamp"
          echo "Backing up $original_file to $timestamped_backup"
          if [[ -d "$original_file" ]]; then
            cp -R "$original_file" "$timestamped_backup"
          else
            cp "$original_file" "$timestamped_backup"
          fi
        fi
      }

      # Smart backup function for managed files (backup then remove original)
      smart_backup_managed() {
        local original_file="$1"
        local backup_suffix="${cfg.backupSuffix}"
        local timestamp_format="${cfg.timestampFormat}"
        local backup_base="$original_file.$backup_suffix"

        if [[ -L "$original_file" ]]; then
          echo "Smart Backup: $original_file is a symlink, skipping removal."
          return 0
        fi

        if [[ -f "$original_file" || -d "$original_file" ]]; then
          local timestamp=$(date +"$timestamp_format")
          local timestamped_backup="$backup_base-$timestamp"
          echo "Backing up and removing $original_file to $timestamped_backup"
          mv "$original_file" "$timestamped_backup"
        fi
      }

      # First, rotate any existing HM backups for all configured paths to avoid clobber errors
      ${lib.concatMapStringsSep "\n" (file: ''
        expanded_file=$(eval echo "${file}")
        rotate_hm_backup "$expanded_file"
      '') (cfg.files ++ cfg.managedFiles)}

      # Backup all configured files (non-destructive)
      ${lib.concatMapStringsSep "\n" (file: ''
        expanded_file=$(eval echo "${file}")
        smart_backup "$expanded_file"
      '') cfg.files}

      # Backup and remove all managed files (destructive)
      ${lib.concatMapStringsSep "\n" (file: ''
        expanded_file=$(eval echo "${file}")
        smart_backup_managed "$expanded_file"
      '') cfg.managedFiles}

      echo "Smart Backup: Backup process completed."
    '';
  };
}

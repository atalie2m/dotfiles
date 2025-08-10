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
  # Use a stable extension (e.g. ".backup"). We'll rotate any existing files with that
  # extension to a timestamped variant before HM runs to avoid clobber errors.
  darwin.ifEnabled = { cfg, ... }: {
    # Keep HM backup extension simple; rotate existing backups ourselves.
    home-manager.backupFileExtension = cfg.backupSuffix;

    # Rotate any existing HM backups before Home Manager runs (pre-activation),
    # so HM won't attempt to overwrite an existing backup and fail.
    system.activationScripts.rotateHmBackupsPre = {
      deps = [ ];
      text = ''
        echo "Smart Backup: Pre-activation rotation of existing HM backups (*.${cfg.backupSuffix})"
        # Run as invoking user so $HOME expands correctly
        if [[ -n ''${SUDO_USER:-} ]]; then
          sudo -u "$SUDO_USER" sh -lc '
            set -e
            timestamp_format="${cfg.timestampFormat}"
            files=(
              ${lib.concatMapStringsSep "\n              " (file: "\"${file}\"") (cfg.files ++ cfg.managedFiles)}
            )
            for f in "''${files[@]}"; do
              expanded_file=$(eval echo "$f")
              candidate="$expanded_file.${cfg.backupSuffix}"
              if [[ -e "$candidate" ]]; then
                ts=$(date +"$timestamp_format")
                echo "Rotating pre-existing HM backup $candidate to $candidate-$ts"
                mv "$candidate" "$candidate-$ts"
              fi
              # Proactively back up the original file before HM force-links the new one
              if [[ -e "$expanded_file" && ! -L "$expanded_file" ]]; then
                ts=$(date +"$timestamp_format")
                echo "Backing up original file $expanded_file to $expanded_file.${cfg.backupSuffix}-$ts"
                cp -R "$expanded_file" "$expanded_file.${cfg.backupSuffix}-$ts"
              fi
            done
          '
        else
          echo "Smart Backup: SUDO_USER not set; skipping pre-activation rotation"
        fi
      '';
    };
  };

  home.ifEnabled = { cfg, ... }: {
    # Early rotation in Home Manager activation (low order value).
    # Note: We also rotate in nix-darwin pre-activation above; this is an extra safeguard.
    home.activation.rotateHmBackups = lib.mkOrder 5 ''
      echo "Smart Backup: HM pre-rotation of existing HM backups (*.${cfg.backupSuffix})"
      timestamp_format="${cfg.timestampFormat}"
      files=(
        ${lib.concatMapStringsSep "\n        " (file: "\"${file}\"") (cfg.files ++ cfg.managedFiles)}
      )
      for f in "''${files[@]}"; do
        expanded_file=$(eval echo "$f")
        candidate="$expanded_file.${cfg.backupSuffix}"
        if [[ -e "$candidate" ]]; then
          ts=$(date +"$timestamp_format")
          echo "Rotating pre-existing HM backup $candidate to $candidate-$ts (HM)"
          mv "$candidate" "$candidate-$ts"
        fi
      done
    '';

    # Run early to try to precede Home Manager's linkGeneration.
    home.activation.smartBackup = lib.mkOrder 50 ''
        echo "Smart Backup: Starting backup process..."

        # Rotate existing Home Manager backup (only the configured suffix) to timestamped name
        rotate_hm_backup() {
          local original_file="$1"
          local backup_suffix="${cfg.backupSuffix}"
          local timestamp_format="${cfg.timestampFormat}"
          local hm_backup_file="$original_file.$backup_suffix"
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

{ delib, lib, ... }:

delib.module {
  name = "tools.system.smartBackup";

  options = with delib; moduleOptions {
    enable = boolOption false;
    files = listOfOption str [ ];
    managedFiles = listOfOption str [
      "$HOME/.config/karabiner/karabiner.json"
    ];
    backupSuffix = strOption "backup";
    timestampFormat = strOption "%Y%m%d-%H%M%S";
  };

  myconfig = {
    always = { parent, ... }: {
      tools.system.smartBackup.enable = lib.mkDefault parent.enable;
    };
  };

  # Enable Home Manager's built-in backup of conflicting files.
  # Use a stable extension (e.g. ".backup"). We'll rotate any existing files with that
  # extension to a timestamped variant before HM runs to avoid clobber errors.
  darwin.ifEnabled = { cfg, myconfig, ... }:
    let
      homeDirectory = myconfig.facts.user.homeDirectory or myconfig.constants.homeDirectory or "";
      resolveHomePath = file:
        if homeDirectory == "" then file
        else if file == "$HOME" then homeDirectory
        else if lib.hasPrefix "$HOME/" file then "${homeDirectory}/${lib.removePrefix "$HOME/" file}"
        else file;
      backupPaths = map resolveHomePath (cfg.files ++ cfg.managedFiles);
    in
    {
      # Keep HM backup extension simple; rotate existing backups ourselves.
      home-manager.backupFileExtension = cfg.backupSuffix;

      # Rotate any existing HM backups before Home Manager runs (pre-activation),
      # so HM won't attempt to overwrite an existing backup and fail.
      system.activationScripts.rotateHmBackupsPre = {
        deps = [ ];
        text = ''
          echo "Smart Backup: Pre-activation rotation of existing HM backups (*.${cfg.backupSuffix})"
          if [[ -n ''${SUDO_USER:-} ]]; then
            sudo -u "$SUDO_USER" bash -lc '
              set -euo pipefail
              timestamp_format="${cfg.timestampFormat}"
              files=(
                ${lib.concatMapStringsSep "\n              " lib.escapeShellArg backupPaths}
              )
              for expanded_file in "''${files[@]}"; do
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

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      homeDirectory = myconfig.facts.user.homeDirectory or myconfig.constants.homeDirectory or "";
      resolveHomePath = file:
        if homeDirectory == "" then file
        else if file == "$HOME" then homeDirectory
        else if lib.hasPrefix "$HOME/" file then "${homeDirectory}/${lib.removePrefix "$HOME/" file}"
        else file;
      backupPaths = map resolveHomePath (cfg.files ++ cfg.managedFiles);
      userBackupPaths = map resolveHomePath cfg.files;
      managedBackupPaths = map resolveHomePath cfg.managedFiles;
    in
    {
      # Early rotation in Home Manager activation (low order value).
      # Note: We also rotate in nix-darwin pre-activation above; this is an extra safeguard.
      home.activation.rotateHmBackups = lib.mkOrder 5 ''
        echo "Smart Backup: HM pre-rotation of existing HM backups (*.${cfg.backupSuffix})"
        timestamp_format="${cfg.timestampFormat}"
        files=(
          ${lib.concatMapStringsSep "\n        " lib.escapeShellArg backupPaths}
        )
        for expanded_file in "''${files[@]}"; do
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
          rotate_hm_backup ${lib.escapeShellArg file}
        '') backupPaths}

        # Backup all configured files (non-destructive)
        ${lib.concatMapStringsSep "\n" (file: ''
          smart_backup ${lib.escapeShellArg file}
        '') userBackupPaths}

        # Backup and remove all managed files (destructive)
        ${lib.concatMapStringsSep "\n" (file: ''
          smart_backup_managed ${lib.escapeShellArg file}
        '') managedBackupPaths}

        echo "Smart Backup: Backup process completed."
      '';
    };
}

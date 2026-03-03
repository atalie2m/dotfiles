{ delib, lib, dotlib, ... }:

# macOS Terminal.app profile management via .terminal imports.

delib.module {
  name = "tools.terminal.terminalApp";

  options = with delib; moduleOptions {
    enable = boolOption false;
    profiles = attrsOption { };
    extraProfiles = attrsOption { };
    defaultProfile = strOption "";
    startupProfile = strOption "";
    forceImport = boolOption false;
    failOnDrift = boolOption true;
  };

  myconfig = {
    always = dotlib.mkEnableDefault "tools.terminal.terminalApp.enable";
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      profileMap = cfg.profiles // cfg.extraProfiles;
      profileNames = lib.attrNames profileMap;
      profileSpecs = map (name: "${name}|${profileMap.${name}}") profileNames;
    in
    {
      assertions = [
        {
          assertion = cfg.defaultProfile == "" || builtins.hasAttr cfg.defaultProfile profileMap;
          message = "tools.terminal.terminalApp.defaultProfile must be defined in profiles/extraProfiles.";
        }
        {
          assertion = cfg.startupProfile == "" || builtins.hasAttr cfg.startupProfile profileMap;
          message = "tools.terminal.terminalApp.startupProfile must be defined in profiles/extraProfiles.";
        }
      ];

      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.configureTerminalProfiles = lib.mkOrder 600 ''
            set -eu

            realPlist="$HOME/Library/Preferences/com.apple.Terminal.plist"
            workPlist="$(mktemp "''${TMPDIR:-/tmp}/terminal-prefs.XXXXXX.plist")"
            stateUpdateList="$(mktemp "''${TMPDIR:-/tmp}/terminal-state-updates.XXXXXX")"
            plist="$workPlist"

            defaultProfile=${lib.escapeShellArg cfg.defaultProfile}
            startupProfile=${lib.escapeShellArg cfg.startupProfile}
            forceImport=${if cfg.forceImport then "1" else "0"}
            failOnDrift=${if cfg.failOnDrift then "1" else "0"}

            forceImportFlagFile="/tmp/dotfiles-terminal-force-import"
            stateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/terminal-app"
            profileStateDir="$stateDir/profiles"
            snapshotDir="$stateDir/snapshots"
            backupDir="$stateDir/backups"
            legacyStateDir="''${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/terminal/profiles"
            backupPath="$backupDir/com.apple.Terminal.$(/bin/date +%Y%m%d-%H%M%S).plist"
            forceImportSource=""
            : "''${DRY_RUN_CMD:=}"

            cleanup() {
              rm -f "$workPlist" "$stateUpdateList"
            }
            trap cleanup EXIT

            has_profile_in_plist() {
              plistPath="$1"
              name="$2"
              if [ -f "$plistPath" ] && /usr/libexec/PlistBuddy -c "Print :\"Window Settings\":\"$name\":name" "$plistPath" >/dev/null 2>&1; then
                return 0
              fi
              return 1
            }

            has_profile() {
              has_profile_in_plist "$plist" "$1"
            }

            ensure_window_settings_dict() {
              if [ ! -f "$plist" ]; then
                /usr/libexec/PlistBuddy -c "Clear dict" "$plist" >/dev/null 2>&1 || true
              fi

              if ! /usr/libexec/PlistBuddy -c "Print :\"Window Settings\"" "$plist" >/dev/null 2>&1; then
                /usr/libexec/PlistBuddy -c "Add :\"Window Settings\" dict" "$plist" >/dev/null 2>&1 || true
              fi
            }

            canonical_hash_from_file() {
              file="$1"
              tmpdir="$(mktemp -d)"
              srcBin="$tmpdir/source.bin"

              if ! /usr/bin/plutil -convert binary1 -o "$srcBin" "$file" >/dev/null 2>&1; then
                rm -rf "$tmpdir"
                return 1
              fi

              /usr/bin/shasum -a 256 "$srcBin" | /usr/bin/awk '{print $1}'
              rm -rf "$tmpdir"
              return 0
            }

            canonical_hash_from_profile_in_plist() {
              plistPath="$1"
              name="$2"
              tmpdir="$(mktemp -d)"
              curXml="$tmpdir/current.xml"
              curBin="$tmpdir/current.bin"

              if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$name\"" "$plistPath" >"$curXml" 2>/dev/null; then
                rm -rf "$tmpdir"
                return 1
              fi
              if ! /usr/bin/plutil -convert binary1 -o "$curBin" "$curXml" >/dev/null 2>&1; then
                rm -rf "$tmpdir"
                return 1
              fi

              /usr/bin/shasum -a 256 "$curBin" | /usr/bin/awk '{print $1}'
              rm -rf "$tmpdir"
              return 0
            }

            canonical_hash_from_profile() {
              canonical_hash_from_profile_in_plist "$plist" "$1"
            }

            profile_state_key() {
              name="$1"
              shortHash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print substr($1, 1, 12)}')"
              prefix="$(printf '%s' "$name" | /usr/bin/tr '[:space:]' '-' | /usr/bin/tr -cd '[:alnum:]._-')"
              if [ -z "$prefix" ]; then
                prefix="profile"
              fi
              printf '%s.%s\n' "$prefix" "$shortHash"
            }

            profile_state_file() {
              name="$1"
              key="$(profile_state_key "$name")"
              printf '%s/%s.sha256\n' "$profileStateDir" "$key"
            }

            legacy_state_file() {
              name="$1"
              fullHash="$(printf '%s' "$name" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"
              printf '%s/%s.sha256\n' "$legacyStateDir" "$fullHash"
            }

            read_last_applied_hash() {
              name="$1"
              stateFile="$(profile_state_file "$name")"
              if [ -f "$stateFile" ]; then
                /usr/bin/head -n 1 "$stateFile" | /usr/bin/tr -d '[:space:]'
                return 0
              fi

              legacyFile="$(legacy_state_file "$name")"
              if [ -f "$legacyFile" ]; then
                /usr/bin/head -n 1 "$legacyFile" | /usr/bin/tr -d '[:space:]'
              fi
            }

            is_sha256_hash() {
              value="$1"
              printf '%s' "$value" | /usr/bin/grep -Eq '^[0-9a-fA-F]{64}$'
            }

            queue_state_update() {
              name="$1"
              if /usr/bin/grep -Fxq "$name" "$stateUpdateList" 2>/dev/null; then
                return 0
              fi
              printf '%s\n' "$name" >>"$stateUpdateList"
            }

            write_last_applied_hash() {
              name="$1"
              hash="$2"
              stateFile="$(profile_state_file "$name")"

              if [ -n "$DRY_RUN_CMD" ]; then
                echo "terminal-app: dry-run: would write lastApplied for $name to $stateFile" >&2
                return 0
              fi

              if ! /bin/mkdir -p "$profileStateDir"; then
                echo "terminal-app: failed to create state dir: $profileStateDir" >&2
                return 1
              fi

              printf '%s\n' "$hash" >"$stateFile"
            }

            write_last_applied_snapshot() {
              name="$1"
              plistPath="$2"
              key="$(profile_state_key "$name")"
              snapshotPath="$snapshotDir/$key.plist"
              tmpSnapshot="$(mktemp "''${TMPDIR:-/tmp}/terminal-snapshot.XXXXXX.plist")"

              if [ -n "$DRY_RUN_CMD" ]; then
                echo "terminal-app: dry-run: would write snapshot for $name to $snapshotPath" >&2
                rm -f "$tmpSnapshot"
                return 0
              fi

              if ! /bin/mkdir -p "$snapshotDir"; then
                echo "terminal-app: failed to create snapshot dir: $snapshotDir" >&2
                rm -f "$tmpSnapshot"
                return 1
              fi

              if ! /usr/libexec/PlistBuddy -x -c "Print :\"Window Settings\":\"$name\"" "$plistPath" >"$tmpSnapshot" 2>/dev/null; then
                echo "terminal-app: failed to export snapshot for profile: $name" >&2
                rm -f "$tmpSnapshot"
                return 1
              fi

              if ! /usr/bin/plutil -convert xml1 -o "$snapshotPath" "$tmpSnapshot" >/dev/null 2>&1; then
                echo "terminal-app: failed to normalize snapshot for profile: $name" >&2
                rm -f "$tmpSnapshot"
                return 1
              fi

              rm -f "$tmpSnapshot"
              return 0
            }

            if ! /usr/bin/defaults export com.apple.Terminal - >"$workPlist" 2>/dev/null; then
              if [ -f "$realPlist" ]; then
                cp "$realPlist" "$workPlist"
              else
                /usr/libexec/PlistBuddy -c "Clear dict" "$workPlist" >/dev/null 2>&1 || true
              fi
            fi

            # One-shot override: DOTFILES_TERMINAL_FORCE_IMPORT=1 nix run .#apply -- ...
            if [ "''${DOTFILES_TERMINAL_FORCE_IMPORT:-0}" = "1" ]; then
              forceImport=1
              forceImportSource="environment"
            elif [ -f "$forceImportFlagFile" ]; then
              forceImport=1
              forceImportSource="flag-file"
            fi

            if [ "$forceImport" -eq 1 ] && [ -n "$forceImportSource" ]; then
              echo "terminal-app: force import enabled via $forceImportSource" >&2
            fi

            driftDetected=0
            configFailures=0
            for entry in ${lib.escapeShellArgs profileSpecs}; do
              name="''${entry%%|*}"
              file="''${entry#*|}"

              if [ ! -f "$file" ]; then
                echo "terminal-app: profile file not found: $file" >&2
                case "$file" in
                  /nix/store/*-source/*)
                    echo "terminal-app: hint: this usually means the file is not tracked by git yet." >&2
                    echo "terminal-app: hint: run: git add apps/terminal/*.terminal" >&2
                    ;;
                esac
                configFailures=1
                continue
              fi

              desiredHash="$(canonical_hash_from_file "$file" || true)"
              if [ -z "$desiredHash" ]; then
                echo "terminal-app: failed to hash profile file: $file" >&2
                configFailures=1
                continue
              fi

              actualExists=0
              actualHash=""
              if has_profile "$name"; then
                actualExists=1
                actualHash="$(canonical_hash_from_profile "$name" || true)"
                if [ -z "$actualHash" ]; then
                  echo "terminal-app: failed to hash Terminal profile: $name" >&2
                  configFailures=1
                  continue
                fi
              fi

              lastHash="$(read_last_applied_hash "$name")"

              if [ -n "$lastHash" ]; then
                if ! is_sha256_hash "$lastHash"; then
                  echo "terminal-app: invalid lastApplied hash for profile: $name" >&2
                  echo "terminal-app:   state file: $(profile_state_file "$name")" >&2
                  configFailures=1
                  continue
                fi

                if [ "$actualExists" -eq 0 ]; then
                  driftDetected=1
                  echo "terminal-app: drift detected for profile: $name" >&2
                  echo "terminal-app:   reason: profile missing in Terminal.app but lastApplied exists" >&2
                  continue
                fi

                if [ "$actualHash" = "$lastHash" ]; then
                  continue
                fi

                if [ "$actualHash" = "$desiredHash" ]; then
                  queue_state_update "$name"
                  continue
                fi

                if [ "$desiredHash" = "$lastHash" ]; then
                  driftDetected=1
                  echo "terminal-app: drift detected for profile: $name" >&2
                  echo "terminal-app:   reason: current changed outside dotfiles" >&2
                  echo "terminal-app:   source file: $file" >&2
                  echo "terminal-app:   lastApplied: $lastHash" >&2
                  continue
                fi

                driftDetected=1
                echo "terminal-app: conflict detected for profile: $name" >&2
                echo "terminal-app:   reason: both repo and current changed from lastApplied" >&2
                echo "terminal-app:   source file: $file" >&2
                echo "terminal-app:   lastApplied: $lastHash" >&2
                continue
              fi

              if [ "$actualExists" -eq 1 ] && [ "$actualHash" != "$desiredHash" ]; then
                driftDetected=1
                echo "terminal-app: drift detected for profile: $name" >&2
                echo "terminal-app:   reason: existing profile differs from repo and no lastApplied state" >&2
                continue
              fi

              if [ "$actualExists" -eq 1 ] && [ "$actualHash" = "$desiredHash" ]; then
                queue_state_update "$name"
              fi
            done

            if [ "$configFailures" -eq 1 ]; then
              echo "terminal-app: apply aborted because profile inputs or state files are invalid." >&2
              exit 1
            fi

            if [ "$driftDetected" -eq 1 ] && [ "$failOnDrift" -eq 1 ] && [ "$forceImport" -eq 0 ]; then
              echo "terminal-app: apply aborted because Terminal profile drift was detected." >&2
              echo "terminal-app: inspect drift with:" >&2
              echo "terminal-app:   nix run .#dotfiles -- terminal sync --check" >&2
              echo "terminal-app: adopt current Terminal settings into repo with:" >&2
              echo "terminal-app:   nix run .#dotfiles -- terminal sync --adopt" >&2
              echo "terminal-app: then re-apply with force import only when needed:" >&2
              echo "terminal-app:   DOTFILES_TERMINAL_FORCE_IMPORT=1 nix run .#apply -- --host <host>" >&2
              exit 1
            fi

            importFailures=0
            ensure_window_settings_dict
            for entry in ${lib.escapeShellArgs profileSpecs}; do
              name="''${entry%%|*}"
              file="''${entry#*|}"

              if [ ! -f "$file" ]; then
                echo "terminal-app: profile file not found: $file" >&2
                case "$file" in
                  /nix/store/*-source/*)
                    echo "terminal-app: hint: this usually means the file is not tracked by git yet." >&2
                    echo "terminal-app: hint: run: git add apps/terminal/*.terminal" >&2
                    ;;
                esac
                importFailures=1
                continue
              fi

              desiredHash="$(canonical_hash_from_file "$file" || true)"
              if [ -z "$desiredHash" ]; then
                echo "terminal-app: failed to hash profile file: $file" >&2
                importFailures=1
                continue
              fi

              actualExists=0
              actualHash=""
              if has_profile "$name"; then
                actualExists=1
                actualHash="$(canonical_hash_from_profile "$name" || true)"
                if [ -z "$actualHash" ]; then
                  echo "terminal-app: failed to hash Terminal profile: $name" >&2
                  importFailures=1
                  continue
                fi
              fi

              lastHash="$(read_last_applied_hash "$name")"

              shouldImport=0
              if [ "$forceImport" -eq 1 ]; then
                shouldImport=1
              else
                if [ "$actualExists" -eq 0 ]; then
                  shouldImport=1
                elif [ -n "$lastHash" ] && [ "$actualHash" = "$lastHash" ] && [ "$actualHash" != "$desiredHash" ]; then
                  shouldImport=1
                fi
              fi

              if [ "$shouldImport" -eq 1 ]; then
                if has_profile "$name"; then
                  # Replace profile deterministically from .terminal content.
                  $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Delete :\"Window Settings\":\"$name\"" "$plist" >/dev/null 2>&1 || true
                fi

                if ! $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Add :\"Window Settings\":\"$name\" dict" "$plist"; then
                  echo "terminal-app: failed to create profile container: $name" >&2
                  importFailures=1
                  continue
                fi

                if ! $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Merge \"$file\" :\"Window Settings\":\"$name\"" "$plist"; then
                  echo "terminal-app: failed to merge profile file into plist: $name ($file)" >&2
                  importFailures=1
                  continue
                fi

                if ! has_profile "$name"; then
                  echo "terminal-app: profile still missing after merge: $name" >&2
                  importFailures=1
                  continue
                fi

                mergedHash="$(canonical_hash_from_profile "$name" || true)"
                if [ -z "$mergedHash" ]; then
                  echo "terminal-app: failed to hash merged profile: $name" >&2
                  importFailures=1
                  continue
                fi

                if [ "$mergedHash" != "$desiredHash" ]; then
                  echo "terminal-app: merged profile hash mismatch: $name" >&2
                  importFailures=1
                  continue
                fi

                queue_state_update "$name"
                continue
              fi

              if [ "$actualExists" -eq 1 ] && [ "$actualHash" = "$desiredHash" ]; then
                queue_state_update "$name"
              fi
            done

            if [ "$importFailures" -eq 1 ]; then
              echo "terminal-app: apply aborted because one or more profiles could not be imported." >&2
              echo "terminal-app: review the profile files under apps/terminal and re-run with one-shot force import:" >&2
              echo "terminal-app:   DOTFILES_TERMINAL_FORCE_IMPORT=1 nix run .#apply -- --host <host>" >&2
              exit 1
            fi

            if [ -f "$realPlist" ]; then
              if [ -n "$DRY_RUN_CMD" ]; then
                echo "terminal-app: dry-run: would back up $realPlist to $backupPath" >&2
              else
                if ! /bin/mkdir -p "$backupDir"; then
                  echo "terminal-app: failed to create backup dir: $backupDir" >&2
                  exit 1
                fi
                if ! /bin/cp "$realPlist" "$backupPath"; then
                  echo "terminal-app: failed to back up $realPlist to $backupPath" >&2
                  exit 1
                fi
                echo "terminal-app: backup saved: $backupPath" >&2
              fi
            fi

            defaultsFailures=0
            if [ -n "$defaultProfile" ]; then
              if has_profile "$defaultProfile"; then
                $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Delete :\"Default Window Settings\"" "$plist" >/dev/null 2>&1 || true
                if ! $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Add :\"Default Window Settings\" string \"$defaultProfile\"" "$plist"; then
                  echo "terminal-app: failed to set Default Window Settings in plist: $defaultProfile" >&2
                  defaultsFailures=1
                fi
              else
                echo "terminal-app: defaultProfile not found in Terminal settings: $defaultProfile" >&2
                defaultsFailures=1
              fi
            fi

            if [ -n "$startupProfile" ]; then
              if has_profile "$startupProfile"; then
                $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Delete :\"Startup Window Settings\"" "$plist" >/dev/null 2>&1 || true
                if ! $DRY_RUN_CMD /usr/libexec/PlistBuddy -c "Add :\"Startup Window Settings\" string \"$startupProfile\"" "$plist"; then
                  echo "terminal-app: failed to set Startup Window Settings in plist: $startupProfile" >&2
                  defaultsFailures=1
                fi
              else
                echo "terminal-app: startupProfile not found in Terminal settings: $startupProfile" >&2
                defaultsFailures=1
              fi
            fi

            if [ "$defaultsFailures" -eq 1 ]; then
              exit 1
            fi

            if ! $DRY_RUN_CMD /usr/bin/defaults import com.apple.Terminal "$plist"; then
              echo "terminal-app: failed to import updated Terminal preferences" >&2
              exit 1
            fi

            if [ -z "$DRY_RUN_CMD" ]; then
              if [ -n "$defaultProfile" ]; then
                currentDefault="$(/usr/bin/defaults read com.apple.Terminal "Default Window Settings" 2>/dev/null || true)"
                if [ "$currentDefault" != "$defaultProfile" ]; then
                  echo "terminal-app: failed to apply Default Window Settings to $defaultProfile (current: $currentDefault)" >&2
                  exit 1
                fi
              fi

              if [ -n "$startupProfile" ]; then
                currentStartup="$(/usr/bin/defaults read com.apple.Terminal "Startup Window Settings" 2>/dev/null || true)"
                if [ "$currentStartup" != "$startupProfile" ]; then
                  echo "terminal-app: failed to apply Startup Window Settings to $startupProfile (current: $currentStartup)" >&2
                  exit 1
                fi
              fi

              stateFailures=0
              while IFS= read -r stateName; do
                [ -z "$stateName" ] && continue

                appliedHash="$(canonical_hash_from_profile_in_plist "$realPlist" "$stateName" || true)"
                if [ -z "$appliedHash" ]; then
                  echo "terminal-app: failed to hash applied profile for state update: $stateName" >&2
                  stateFailures=1
                  continue
                fi

                if ! write_last_applied_hash "$stateName" "$appliedHash"; then
                  echo "terminal-app: failed to write lastApplied state for profile: $stateName" >&2
                  stateFailures=1
                  continue
                fi

                if ! write_last_applied_snapshot "$stateName" "$realPlist"; then
                  echo "terminal-app: failed to write snapshot for profile: $stateName" >&2
                  stateFailures=1
                fi
              done <"$stateUpdateList"

              if [ "$stateFailures" -eq 1 ]; then
                exit 1
              fi
            fi

            $DRY_RUN_CMD /usr/bin/killall cfprefsd >/dev/null 2>&1 || true
          '';
        })
      ];
    };
}

{ delib, lib, ... }:

# macOS GUI preferences for Dock, trackpad, Finder, and window management.

delib.module {
  name = "tools.system.macosUi";

  options = with delib; moduleOptions {
    enable = boolOption false;

    dock = {
      enable = boolOption true;
      # Show hidden apps as translucent Dock icons.
      showHiddenApplications = boolOption true;
      showRecents = boolOption false;
      tileSize = intOption 54;
      minimizeToApplication = boolOption false;
      mruSpaces = boolOption false;
      # "Displays have separate Spaces" in Mission Control: each screen has its own Space strip.
      separateSpacesPerDisplay = boolOption true;
      autohide = boolOption true;
      autohideDelay = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
      autohideTimeModifier = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
      };
    };

    trackpad = {
      threeFingerDrag = boolOption true;
      naturalScrolling = boolOption false;
    };

    windowManager = {
      tiledWindowMargins = boolOption false;
    };

    finder = {
      showHiddenFiles = boolOption true;
      showAllExtensions = boolOption true;
      showPathInTitleBar = boolOption true;
      sortFoldersFirst = boolOption true;
      showExternalHardDrivesOnDesktop = boolOption true;
      showRemovableMediaOnDesktop = boolOption true;
      showMountedServersOnDesktop = boolOption true;
      showStatusBar = boolOption true;
      showPathBar = boolOption true;
      searchCurrentFolderByDefault = boolOption true;
      writeDSStoreOnNetworkVolumes = boolOption false;
      writeDSStoreOnUSBVolumes = boolOption false;
      warnOnEmptyTrash = boolOption true;
      showRecentTags = boolOption false;
    };
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      threeFingerDragEnabled = if cfg.trackpad.threeFingerDrag then 1 else 0;
      searchScope = if cfg.finder.searchCurrentFolderByDefault then "SCcf" else "MC";
      dockDefaults = lib.optionalAttrs cfg.dock.enable {
        autohide = cfg.dock.autohide;
        showhidden = cfg.dock.showHiddenApplications;
        "show-recents" = cfg.dock.showRecents;
        tilesize = cfg.dock.tileSize;
        "minimize-to-application" = cfg.dock.minimizeToApplication;
        "mru-spaces" = cfg.dock.mruSpaces;
      };
      dockTimingDefaults =
        lib.optionalAttrs (cfg.dock.enable && cfg.dock.autohideDelay != null)
          {
            "autohide-delay" = cfg.dock.autohideDelay;
          }
        // lib.optionalAttrs (cfg.dock.enable && cfg.dock.autohideTimeModifier != null) {
          # Treat this as 0.1s steps so we can tune smoothly without float options.
          "autohide-time-modifier" = cfg.dock.autohideTimeModifier / 10;
        };
      trackpadDefaults = lib.optionalAttrs cfg.trackpad.threeFingerDrag {
        "com.apple.AppleMultitouchTrackpad" = {
          TrackpadThreeFingerDrag = threeFingerDragEnabled;
        };

        "com.apple.driver.AppleBluetoothMultitouchTrackpad" = {
          TrackpadThreeFingerDrag = threeFingerDragEnabled;
        };
      };
      finderDefaults = {
        AppleShowAllFiles = cfg.finder.showHiddenFiles;
        AppleShowAllExtensions = cfg.finder.showAllExtensions;
        ShowPathbar = cfg.finder.showPathBar;
        ShowStatusBar = cfg.finder.showStatusBar;
        _FXShowPosixPathInTitle = cfg.finder.showPathInTitleBar;
        _FXSortFoldersFirst = cfg.finder.sortFoldersFirst;
        ShowExternalHardDrivesOnDesktop = cfg.finder.showExternalHardDrivesOnDesktop;
        ShowMountedServersOnDesktop = cfg.finder.showMountedServersOnDesktop;
        ShowRecentTags = cfg.finder.showRecentTags;
        ShowRemovableMediaOnDesktop = cfg.finder.showRemovableMediaOnDesktop;
        FXDefaultSearchScope = searchScope;
        WarnOnEmptyTrash = cfg.finder.warnOnEmptyTrash;
        FXEnableExtensionChangeWarning = false;
      };

      desktopServicesDefaults = {
        DSDontWriteNetworkStores = !cfg.finder.writeDSStoreOnNetworkVolumes;
        DSDontWriteUSBStores = !cfg.finder.writeDSStoreOnUSBVolumes;
      };

      windowManagerDefaults = {
        EnableTiledWindowMargins = cfg.windowManager.tiledWindowMargins;
      };
    in
    {
      system.defaults = {
        NSGlobalDomain = {
          "com.apple.swipescrolldirection" = cfg.trackpad.naturalScrolling;
        };

        CustomUserPreferences = {
          "com.apple.dock" = dockDefaults // dockTimingDefaults;
          "com.apple.finder" = finderDefaults;
          "com.apple.desktopservices" = desktopServicesDefaults;
          "com.apple.WindowManager" = windowManagerDefaults;
          "com.apple.spaces" = {
            # spans-displays false => separate Spaces per display (not one strip spanning monitors).
            "spans-displays" = !cfg.dock.separateSpacesPerDisplay;
          };
        } // trackpadDefaults;
      };
    };
}

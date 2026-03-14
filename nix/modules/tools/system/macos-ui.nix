{ delib, lib, dotlib, ... }:

# macOS GUI preferences for keyboard, Dock, trackpad, Finder, and window management.

delib.module {
  name = "tools.system.macosUi";

  options = with delib; moduleOptions {
    enable = boolOption false;

    keyRepeat = {
      enable = boolOption true;
      rate = intOption 1;
      initialDelay = intOption 15;
      pressAndHold = boolOption false;
    };

    keyboard = {
      useStandardFunctionKeys = boolOption true;
    };

    dock = {
      showRecents = boolOption false;
      tileSize = intOption 54;
      mruSpaces = boolOption false;
      autohide = boolOption true;
      autohideDelay = intOption 0;
      autohideTimeModifier = intOption 2;
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

  myconfig = {
    always = dotlib.mkEnableDefault "tools.system.macosUi.enable";
  };

  darwin.ifEnabled = { cfg, ... }:
    let
      threeFingerDragEnabled = if cfg.trackpad.threeFingerDrag then 1 else 0;
      searchScope = if cfg.finder.searchCurrentFolderByDefault then "SCcf" else "MC";
      keyRepeatDefaults = lib.optionalAttrs cfg.keyRepeat.enable {
        KeyRepeat = cfg.keyRepeat.rate;
        InitialKeyRepeat = cfg.keyRepeat.initialDelay;
        ApplePressAndHoldEnabled = cfg.keyRepeat.pressAndHold;
        AppleShowAllExtensions = cfg.finder.showAllExtensions;
        "com.apple.keyboard.fnState" = cfg.keyboard.useStandardFunctionKeys;
      };
      dockDefaults = lib.optionalAttrs cfg.dock.enable {
        autohide = cfg.dock.autohide;
        "autohide-delay" = cfg.dock.autohideDelay;
        # Treat this as 0.1s steps so we can tune smoothly without float options.
        "autohide-time-modifier" = cfg.dock.autohideTimeModifier / 10;
        "show-recents" = cfg.dock.showRecents;
        tilesize = cfg.dock.tileSize;
        magnification = cfg.dock.magnification;
        launchanim = cfg.dock.launchAnimation;
        mineffect = cfg.dock.minimizeEffect;
        "minimize-to-application" = cfg.dock.minimizeToApplication;
        "mru-spaces" = cfg.dock.mruSpaces;
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
        NSGlobalDomain = keyRepeatDefaults // {
          "com.apple.swipescrolldirection" = cfg.trackpad.naturalScrolling;
        };

        CustomUserPreferences = {
          "com.apple.dock" = dockDefaults;
          "com.apple.finder" = finderDefaults;
          "com.apple.desktopservices" = desktopServicesDefaults;
          "com.apple.WindowManager" = windowManagerDefaults;
          "com.apple.spaces" = {
            # Keep Spaces independent per display so switching one monitor does not move the others.
            "spans-displays" = !cfg.dock.onlyPrimaryDisplay;
          };
        } // trackpadDefaults;
      };
    };
}

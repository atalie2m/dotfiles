{ delib, lib, pkgs, ... }:

# Emacs (GUI via Homebrew) + Meow configuration

delib.module {
  name = "tools.editor.emacs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = { parent, ... }: {
      tools.editor.emacs.enable = lib.mkDefault parent.enable;
    };
    ifEnabled = { ... }: {
      tools.system.homebrewNative.enable = lib.mkDefault true;
    };
  };

  darwin.ifEnabled = { ... }: {
    homebrew.taps = lib.mkAfter [
      "d12frosted/emacs-plus"
    ];
    homebrew.casks = lib.mkAfter [
      "emacs-plus-app"
    ];
  };

  home.ifEnabled = { myconfig, ... }:
    let
      dotfilesPath = myconfig.facts.user.dotfilesPath
        or myconfig.constants.dotfilesPath
        or "";
      iconPath = "${dotfilesPath}/apps/emacs/emacs-icon-1.0.icns";
    in
    assert lib.assertMsg (dotfilesPath != "")
      "facts.user.dotfilesPath is required to set emacs-plus icon";
    {
      home.file.".emacs.d/early-init.el".source = ../../../../../apps/emacs/early-init.el;
      home.file.".emacs.d/init.el".source = ../../../../../apps/emacs/init.el;
      home.file.".emacs.d/lisp" = {
        source = ../../../../../apps/emacs/lisp;
        recursive = true;
      };
      home.file.".config/emacs-plus/build.yml".text = ''
        icon:
          url: ${iconPath}
          sha256: 0067c716e0129182951559c5ce1cf583f174f6637558fce7cbf58ac69f9a2933
      '';
    };
}

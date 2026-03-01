{ delib, lib, pkgs, ... }:

# Emacs (GUI via Homebrew) + Meow configuration

let
  mkEnableDefault = import ../../../../lib/mk-enable-default.nix { inherit lib; };
in

delib.module {
  name = "tools.editor.emacs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig = {
    always = mkEnableDefault "tools.editor.emacs.enable";
    ifEnabled = { ... }: {
      tools.system.homebrewNative.enable = lib.mkDefault true;
      tools.system.homebrewNative.taps = lib.mkAfter [
        "d12frosted/emacs-plus"
      ];
      tools.system.homebrewNative.casks = lib.mkAfter [
        "emacs-plus-app"
      ];
    };
  };

  home.ifEnabled = { ... }:
    let
      iconPath = ../../../../../apps/emacs/emacs-icon-1.0.icns;
      hasIcon = builtins.pathExists iconPath;
    in
    {
      home.file.".emacs.d/early-init.el" = {
        force = true;
        source = ../../../../../apps/emacs/early-init.el;
      };
      home.file.".emacs.d/init.el" = {
        force = true;
        source = ../../../../../apps/emacs/init.el;
      };
      home.file.".emacs.d/lisp" = {
        force = true;
        source = ../../../../../apps/emacs/lisp;
        recursive = true;
      };
    } // lib.optionalAttrs hasIcon {
      home.file.".config/emacs-plus/build.yml" = {
        force = true;
        text = ''
          icon:
            url: ${iconPath}
            sha256: 0067c716e0129182951559c5ce1cf583f174f6637558fce7cbf58ac69f9a2933
        '';
      };
    };
}

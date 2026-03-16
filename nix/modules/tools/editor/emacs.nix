{ delib, lib, dotlib, pkgs, repoPaths, ... }:

let
  homebrewOwnership = import (repoPaths.catalog + "/tools/homebrew-ownership.nix");
  homebrewSpec = homebrewOwnership."editor.emacs";
in

# Emacs (GUI via Homebrew) + Meow configuration

delib.module {
  name = "tools.editor.emacs";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  myconfig.ifEnabled = { myconfig, ... }:
    dotlib.ifDarwin myconfig (dotlib.requireHomebrewSpec homebrewSpec);

  home.ifEnabled = { ... }:
    let
      emacsDir = repoPaths.apps + "/emacs";
      iconPath = emacsDir + "/emacs-icon-1.0.icns";
      hasIcon = builtins.pathExists iconPath;
      emacsPackages = with pkgs.emacsPackages; [
        ace-window
        avy
        cape
        consult
        corfu
        embark
        magit
        marginalia
        meow
        meow-tree-sitter
        orderless
        popper
        tempel
        treesit-auto
        treemacs
        use-package
        vertico
        vundo
        which-key
      ];
      emacsFiles = {
        ".emacs.d/early-init.el" = {
          force = true;
          source = emacsDir + "/early-init.el";
        };
        ".emacs.d/init.el" = {
          force = true;
          source = emacsDir + "/init.el";
        };
        ".emacs.d/lisp" = {
          force = true;
          source = emacsDir + "/lisp";
          recursive = true;
        };
      } // lib.optionalAttrs hasIcon {
        ".config/emacs-plus/build.yml" = {
          force = true;
          text = ''
            icon:
              url: ${iconPath}
              sha256: 0067c716e0129182951559c5ce1cf583f174f6637558fce7cbf58ac69f9a2933
          '';
        };
      };
    in
    {
      home.packages = emacsPackages;
      home.file = emacsFiles;
    };
}

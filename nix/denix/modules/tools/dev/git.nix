{ delib, lib, dotlib, ... }:

# Git configuration with user information from constants

delib.module {
  name = "tools.dev.git";

  options = with delib; moduleOptions {
    enable = boolOption false;
    defaultBranch = strOption "main";
    editorCmd = strOption "vim";
    enableSigning = boolOption false;
    extraConfig = attrsOption { };
    lfs = {
      enable = boolOption false;
    };
    aliases = attrsOption {
      # Default useful aliases
      st = "status";
      co = "checkout";
      br = "branch";
      ci = "commit";
      unstage = "reset HEAD --";
      last = "log -1 HEAD";
      visual = "!gitk";
    };
  };

  myconfig = {
    always = dotlib.mkEnableDefaults [
      "tools.dev.git.enable"
      "tools.dev.git.lfs.enable"
    ];
  };

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      fullName = myconfig.constants.fullName;
      email = myconfig.constants.email;
    in
    {
      programs.git = {
        enable = true;

        lfs.enable = cfg.lfs.enable;

        extraConfig = lib.mkMerge [
          {
            init.defaultBranch = cfg.defaultBranch;
            pull.rebase = true;
            push.autoSetupRemote = true;
            core.editor = cfg.editorCmd;
          }
          (lib.mkIf cfg.enableSigning {
            commit.gpgsign = true;
            gpg.format = "openpgp";
          })
          cfg.extraConfig
        ];

        inherit (cfg) aliases;
      }
      // lib.optionalAttrs (fullName != "") { userName = fullName; }
      // lib.optionalAttrs (email != "") { userEmail = email; };
    };
}

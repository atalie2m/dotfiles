{ delib, lib, ... }:

# Git configuration with user information from constants
delib.module {
  name = "tools.dev.git";

  options = with delib; moduleOptions {
    enable = boolOption false;
    defaultBranch = strOption "main";
    editorCmd = strOption "vim";
    enableSigning = boolOption false;
    extraConfig = attrsOption { };
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
    always = { parent, ... }: {
      tools.dev.git.enable = lib.mkDefault parent.enable;
    };
  };

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      fullName = myconfig.constants.fullName;
      email = myconfig.constants.email;
    in
    {
      programs.git = {
        enable = true;

        lfs.enable = (((myconfig.tools or { }).dev or { }).gitLfs or { }).enable or false;

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

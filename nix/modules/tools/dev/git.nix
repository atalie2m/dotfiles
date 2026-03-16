{ delib, lib, ... }:

# Git configuration with identity derived from the canonical host model

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
    delta = {
      enable = boolOption false;
      options = attrsOption { };
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

  home.ifEnabled = { cfg, myconfig, ... }:
    let
      fullName = myconfig.hostContext.user.fullName;
      email = myconfig.hostContext.user.email;
    in
    {
      programs.git = {
        enable = true;

        lfs.enable = cfg.lfs.enable;
        settings = lib.mkMerge [
          {
            init.defaultBranch = cfg.defaultBranch;
            pull.rebase = true;
            push.autoSetupRemote = true;
            core.editor = cfg.editorCmd;
            alias = cfg.aliases;
          }
          (lib.mkIf (fullName != null || email != null) {
            user = lib.mkMerge [
              (lib.mkIf (fullName != null) { name = fullName; })
              (lib.mkIf (email != null) { email = email; })
            ];
          })
          (lib.mkIf cfg.enableSigning {
            commit.gpgsign = true;
            gpg.format = "openpgp";
          })
          cfg.extraConfig
        ];
      };

      programs.delta = lib.mkIf cfg.delta.enable {
        enable = true;
        enableGitIntegration = true;
        options = cfg.delta.options;
      };
    };
}

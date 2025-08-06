{ delib, lib, ... }:

# Git configuration with user information from constants
delib.module {
  name = "git";

  options.git = with delib.options; {
    enable = boolOption false;
    enableLFS = boolOption true;
    defaultBranch = strOption "main";
    enableSigning = boolOption false;
    extraConfig = attrsOption {};
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

  home.ifEnabled = { cfg, myconfig, ... }: {
    programs.git = {
      enable = true;
      userName = myconfig.constants.fullName;
      userEmail = myconfig.constants.email;
      
      lfs.enable = cfg.enableLFS;
      
      extraConfig = {
        init.defaultBranch = cfg.defaultBranch;
        pull.rebase = true;
        push.autoSetupRemote = true;
        core.editor = "code --wait";
        
        # Signing configuration (if enabled)
        commit.gpgsign = lib.mkIf cfg.enableSigning true;
        gpg.format = lib.mkIf cfg.enableSigning "openpgp";
      } // cfg.extraConfig;
      
      inherit (cfg) aliases;
    };
  };
}
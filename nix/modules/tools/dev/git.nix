{ dotmod, config, lib, pkgs, ... }:

# Git configuration with identity derived from the canonical host model

(dotmod.mkModule { inherit config; }) {
  path = "tools.dev.git";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    defaultBranch = strOption "main";
    editorCmd = strOption "vim";
    enableSigning = boolOption false;
    signingKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
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

  myconfigOnEnable = { cfg, myconfig, ... }:
    let
      signingKey =
        if cfg.signingKey != null then
          cfg.signingKey
        else
          myconfig.hostContext.user.signingKey;
      signingEnabled = cfg.enableSigning || signingKey != null;
    in
    lib.mkIf signingEnabled {
      tools.security.gpg.enable = lib.mkDefault true;
    };

  homeOnEnable = { cfg, myconfig, ... }:
    let
      fullName = myconfig.hostContext.user.fullName;
      email = myconfig.hostContext.user.email;
      signingKey =
        if cfg.signingKey != null then
          cfg.signingKey
        else
          myconfig.hostContext.user.signingKey;
      signingEnabled = cfg.enableSigning || signingKey != null;
      tools = myconfig.tools or { };
      toolEnabled = group: tool:
        let
          groupCfg =
            if builtins.hasAttr group tools
            then builtins.getAttr group tools
            else { };
          toolCfg =
            if builtins.hasAttr tool groupCfg
            then builtins.getAttr tool groupCfg
            else { };
        in
        (toolCfg.enable or false);
      difftasticEnabled = toolEnabled "searchText" "difftastic";
      gitAbsorbEnabled =
        (toolEnabled "dev" "gitAbsorb") || (toolEnabled "gitPersonal" "gitAbsorb");
      deltaOptions = {
        navigate = true;
        light = false;
        side-by-side = true;
        line-numbers = true;
        syntax-theme = "Catppuccin Mocha";
        plus-style = "syntax #003800";
        minus-style = "syntax #3f0001";
        hyperlinks = true;
        features = "decorations";
      } // cfg.delta.options;
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
          (lib.mkIf difftasticEnabled {
            diff.tool = "difftastic";
            difftool.difftastic.cmd = ''difft "$LOCAL" "$REMOTE"'';
            pager.difftool = true;
          })
          (lib.mkIf gitAbsorbEnabled {
            alias = {
              absorb = "!git absorb";
              abs = "absorb --and-rebase";
            };
          })
          (lib.mkIf (fullName != null || email != null) {
            user = lib.mkMerge [
              (lib.mkIf (fullName != null) { name = fullName; })
              (lib.mkIf (email != null) { email = email; })
            ];
          })
          (lib.mkIf signingEnabled {
            commit.gpgsign = true;
            gpg = {
              format = "openpgp";
              program = "${pkgs.gnupg}/bin/gpg";
            };
            user = lib.mkIf (signingKey != null) {
              signingKey = signingKey;
            };
          })
          cfg.extraConfig
        ];
      };

      programs.delta = lib.mkIf cfg.delta.enable {
        enable = true;
        enableGitIntegration = true;
        options = deltaOptions;
      };
    };
}

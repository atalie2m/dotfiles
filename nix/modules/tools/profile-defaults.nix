{ delib, lib, pkgs, ... }:

let
  catppuccinBat = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "bat";
    rev = "6810349b28055dce54076712fc05fc68da4b8ec0";
    hash = "sha256-lJapSgRVENTrbmpVyn+UQabC9fpV1G1e+CdlJ090uvg=";
  };

  catppuccinBtop = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "btop";
    rev = "f437574b600f1c6d932627050b15ff5153b58fa3";
    hash = "sha256-mEGZwScVPWGu+Vbtddc/sJ+mNdD2kKienGZVUcTSl+c=";
  };

  catppuccinKitty = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "kitty";
    rev = "43098316202b84d6a71f71aaf8360f102f4d3f1a";
    hash = "sha256-akRkdq8l2opGIg3HZd+Y4eky6WaHgKFQ5+iJMC1bhnQ=";
  };

  catppuccinAlacritty = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "alacritty";
    rev = "f6cb5a5c2b404cdaceaff193b9c52317f62c62f7";
    hash = "sha256-H8bouVCS46h0DgQ+oYY8JitahQDj0V9p2cOoD4cQX+Q=";
  };

  toolEnabled = tools: group: tool:
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

  anyToolEnabled = tools: specs:
    lib.any (spec: toolEnabled tools (builtins.elemAt spec 0) (builtins.elemAt spec 1)) specs;
in
delib.module {
  name = "tools.profileDefaults";

  home.always = { myconfig, ... }:
    let
      tools = myconfig.tools or { };

      batEnabled = anyToolEnabled tools [
        [ "core" "bat" ]
        [ "viewersPreview" "bat" ]
      ];
      ghEnabled = anyToolEnabled tools [
        [ "dev" "gh" ]
        [ "gitPersonal" "gh" ]
      ];
      ghDashEnabled = toolEnabled tools "gitPersonal" "ghDash";
      glowEnabled = toolEnabled tools "viewersPreview" "glow";
      ripgrepEnabled = anyToolEnabled tools [
        [ "core" "ripgrep" ]
        [ "searchText" "ripgrep" ]
      ];
      lazygitEnabled = toolEnabled tools "gitPersonal" "lazygit";
      topgradeEnabled = anyToolEnabled tools [
        [ "shellUx" "topgrade" ]
        [ "nixOperator" "topgrade" ]
      ];
      bottomEnabled = toolEnabled tools "observability" "bottom";
      btopEnabled = toolEnabled tools "observability" "btop";
      fastfetchEnabled = toolEnabled tools "observability" "fastfetch";
      kittyEnabled = toolEnabled tools "terminalVisual" "kitty";
      ghosttyEnabled = toolEnabled tools "terminal" "ghostty";
      alacrittyEnabled = toolEnabled tools "terminal" "alacritty";
      aerospaceEnabled = toolEnabled tools "system" "aerospace";
    in
    {
      programs.alacritty = lib.mkIf alacrittyEnabled {
        enable = true;
        package = null;
        settings = {
          general.import = [ "${catppuccinAlacritty}/catppuccin-mocha.toml" ];
          font = {
            normal = {
              family = "JetBrainsMono Nerd Font";
              style = "Regular";
            };
            size = 14.0;
          };
          window = {
            padding = {
              x = 8;
              y = 8;
            };
            opacity = 0.95;
          };
          colors.draw_bold_text_with_bright_colors = true;
        };
      };

      programs.bat = lib.mkIf batEnabled {
        enable = true;
        config = {
          theme = "Catppuccin Mocha";
          style = "numbers,changes,header,grid";
          paging = "never";
          map-syntax = [ "*.md:Markdown" ];
        };
        themes."Catppuccin Mocha" = {
          src = catppuccinBat;
          file = "themes/Catppuccin Mocha.tmTheme";
        };
      };

      programs.bottom = lib.mkIf bottomEnabled {
        enable = true;
        package = null;
        settings = {
          flags = {
            hide_avg_cpu = true;
            dot_marker = true;
            temperature_type = "celsius";
          };
          colors = {
            table_header_color = "LightCyan";
            avg_cpu_color = "Red";
          };
        };
      };

      programs.btop = lib.mkIf btopEnabled {
        enable = true;
        package = null;
        settings = {
          color_theme = "catppuccin_mocha";
          theme_background = false;
          update_ms = 1500;
          proc_tree = true;
        };
        themes.catppuccin_mocha = "${catppuccinBtop}/themes/catppuccin_mocha.theme";
      };

      programs.fastfetch = lib.mkIf fastfetchEnabled {
        enable = true;
        package = null;
        settings = {
          logo.type = "small";
          modules = [
            "title"
            "separator"
            "os"
            "host"
            "kernel"
            "uptime"
            "packages"
            "shell"
            "display"
            "cpu"
            "gpu"
            "memory"
            "disk"
            "localip"
            "battery"
          ];
        };
      };

      programs.gh = lib.mkIf ghEnabled {
        enable = true;
        settings = {
          git_protocol = "ssh";
          telemetry = "disabled";
          aliases = {
            prc = "pr create --fill --web";
            prm = "pr merge --auto --delete-branch";
            co = "pr checkout";
          };
        };
        extensions = lib.optional ghDashEnabled pkgs.gh-dash;
        gitCredentialHelper.enable = false;
      };

      programs.ghostty = lib.mkIf ghosttyEnabled {
        enable = true;
        package = null;
        settings = {
          font-family = "JetBrainsMono Nerd Font";
          font-size = 14;
          background-opacity = 0.92;
          window-padding-x = 8;
          window-padding-y = 8;
          theme = "catppuccin-mocha";
          macos-titlebar-style = "hidden";
          macos-option-as-alt = true;
        };
      };

      programs.kitty = lib.mkIf kittyEnabled {
        enable = true;
        package = null;
        font = {
          name = "JetBrainsMono Nerd Font";
          size = 14.0;
        };
        settings = {
          background_opacity = "0.95";
          window_padding_width = 8;
          enable_audio_bell = false;
          copy_on_select = true;
        };
        extraConfig = ''
          include ${catppuccinKitty}/themes/mocha.conf
        '';
      };

      programs.lazygit = lib.mkIf lazygitEnabled {
        enable = true;
        package = null;
        settings = {
          gui = {
            theme.lightTheme = false;
            showFileTree = true;
            showRandomTip = false;
          };
          keybinding.universal = {
            quit = "q";
            quit-alt1 = "<c-c>";
          };
        };
      };

      xdg.configFile = lib.mkMerge [
        (lib.mkIf aerospaceEnabled {
          "aerospace/aerospace.toml".text = ''
            start-at-login = true
            enable-normalization-flatten-containers = true
            enable-normalization-opposite-orientation-for-nested-containers = true
            accordion-padding = 30
            default-root-container-layout = "tiles"
            default-root-container-orientation = "auto"

            [workspace-to-monitor-force-assignment]
            1 = "main"
            2 = "main"
            3 = "main"
            4 = "main"
            5 = "main"
            6 = "main"
            7 = "main"
            8 = "main"
            9 = "main"

            [mode.main.binding]
            alt-h = "focus left"
            alt-j = "focus down"
            alt-k = "focus up"
            alt-l = "focus right"
            alt-shift-h = "move left"
            alt-shift-j = "move down"
            alt-shift-k = "move up"
            alt-shift-l = "move right"
            alt-1 = "workspace 1"
            alt-2 = "workspace 2"
            alt-3 = "workspace 3"
            alt-4 = "workspace 4"
            alt-5 = "workspace 5"
            alt-6 = "workspace 6"
            alt-7 = "workspace 7"
            alt-8 = "workspace 8"
            alt-9 = "workspace 9"
            alt-shift-1 = "move-node-to-workspace 1"
            alt-shift-2 = "move-node-to-workspace 2"
            alt-shift-3 = "move-node-to-workspace 3"
            alt-shift-4 = "move-node-to-workspace 4"
            alt-shift-5 = "move-node-to-workspace 5"
            alt-shift-6 = "move-node-to-workspace 6"
            alt-shift-7 = "move-node-to-workspace 7"
            alt-shift-8 = "move-node-to-workspace 8"
            alt-shift-9 = "move-node-to-workspace 9"
            alt-slash = "layout tiles horizontal vertical"
            alt-comma = "layout accordion horizontal vertical"
          '';
        })
        (lib.mkIf glowEnabled {
          "glow/glow.yml".text = ''
            style: "dark"
            pager: true
            mouse: true
          '';
        })
        (lib.mkIf lazygitEnabled {
          "lazygit/config.yml".text = ''
            gui:
              theme:
                lightTheme: false
              showFileTree: true
              showRandomTip: false
            keybinding:
              universal:
                quit: q
                quit-alt1: <c-c>
          '';
        })
        (lib.mkIf ripgrepEnabled {
          "ripgrep/ripgreprc".text = ''
            --smart-case
            --hidden
            --follow
            --glob
            !.git/*
            --glob
            !node_modules/*
            --glob
            !target/*
            --max-columns=200
            --max-columns-preview
            --colors=line:style:bold
            --colors=match:fg:magenta
          '';
        })
        (lib.mkIf topgradeEnabled {
          "topgrade.toml".text = ''
            [misc]
            only = ["nix", "home-manager", "brew", "cargo"]

            [nix]
            use_sudo = true
          '';
        })
      ];

      home.file.".ripgreprc" = lib.mkIf ripgrepEnabled {
        source = pkgs.writeText "ripgreprc" ''
          --smart-case
          --hidden
          --follow
          --glob
          !.git/*
          --glob
          !node_modules/*
          --glob
          !target/*
          --max-columns=200
          --max-columns-preview
          --colors=line:style:bold
          --colors=match:fg:magenta
        '';
      };
    };
}

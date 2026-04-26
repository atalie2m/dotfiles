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
      direnvEnabled = anyToolEnabled tools [
        [ "shell" "direnv" ]
        [ "nixOperator" "direnv" ]
      ];
      nixDirenvEnabled = anyToolEnabled tools [
        [ "shell" "direnv" ]
        [ "nixOperator" "nixDirenv" ]
      ];
      ezaEnabled = anyToolEnabled tools [
        [ "core" "eza" ]
        [ "filesNavigation" "eza" ]
      ];
      fdEnabled = anyToolEnabled tools [
        [ "core" "fd" ]
        [ "filesNavigation" "fd" ]
        [ "searchText" "fd" ]
      ];
      fzfEnabled = anyToolEnabled tools [
        [ "shell" "fzf" ]
        [ "shellUx" "fzf" ]
        [ "searchText" "fzf" ]
      ];
      k9sEnabled = anyToolEnabled tools [
        [ "tuiWorkspace" "k9s" ]
        [ "containerK8sPersonal" "k9s" ]
      ];
      ripgrepEnabled = anyToolEnabled tools [
        [ "core" "ripgrep" ]
        [ "searchText" "ripgrep" ]
      ];
      lazygitEnabled = toolEnabled tools "gitPersonal" "lazygit";
      topgradeEnabled = anyToolEnabled tools [
        [ "shellUx" "topgrade" ]
        [ "nixOperator" "topgrade" ]
      ];
      televisionEnabled = toolEnabled tools "shellUx" "television";
      bottomEnabled = toolEnabled tools "observability" "bottom";
      btopEnabled = toolEnabled tools "observability" "btop";
      fastfetchEnabled = toolEnabled tools "observability" "fastfetch";
      yaziEnabled = toolEnabled tools "filesNavigation" "yazi";
      zellijEnabled = toolEnabled tools "tuiWorkspace" "zellij";
      zshEnabled = (((tools.shell or { }).zsh or { }).enable or false);
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

      programs.direnv = lib.mkIf direnvEnabled {
        enable = true;
        enableBashIntegration = false;
        enableNushellIntegration = false;
        enableZshIntegration = false;
        silent = true;
        nix-direnv.enable = lib.mkIf nixDirenvEnabled true;
        config.global = {
          hide_env_diff = true;
          warn_timeout = "45s";
        };
      };

      programs.fzf = lib.mkIf fzfEnabled {
        enable = true;
        enableBashIntegration = false;
        enableFishIntegration = false;
        enableZshIntegration = false;
        defaultCommand = lib.mkIf fdEnabled "fd --hidden --strip-cwd-prefix --exclude .git";
        defaultOptions = [
          "--height=40%"
          "--layout=reverse"
          "--border=rounded"
          "--info=inline"
          "--prompt=> "
          "--marker=*"
          "--pointer=>"
          "--scrollbar=|"
          "--color=fg:#cdd6f4,bg:#1e1e2e,hl:#f38ba8"
          "--color=fg+:#cdd6f4,bg+:#313244,hl+:#f38ba8"
          "--color=info:#cba6f7,prompt:#89b4fa,pointer:#f5e0dc"
          "--color=marker:#a6e3a1,spinner:#f5e0dc,header:#94e2d5"
        ];
        fileWidgetCommand = lib.mkIf fdEnabled "fd --hidden --strip-cwd-prefix --exclude .git";
        fileWidgetOptions =
          [
            "--select-1"
            "--exit-0"
          ]
          ++ lib.optional batEnabled "--preview=bat --style=numbers --color=always --line-range=:200 {}";
        changeDirWidgetCommand = lib.mkIf fdEnabled "fd --type d --hidden --strip-cwd-prefix --exclude .git";
        changeDirWidgetOptions =
          [
            "--select-1"
            "--exit-0"
          ]
          ++ lib.optional ezaEnabled "--preview=eza --tree --level=2 --icons=auto --color=always {}";
        historyWidgetOptions = [
          "--sort"
          "--exact"
        ];
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

      programs.zsh.initContent = lib.mkIf (zshEnabled && yaziEnabled) (lib.mkOrder 920 ''
        yy() {
          local cwd_file
          cwd_file="$(mktemp -t yazi-cwd.XXXXXX)"
          yazi "$@" --cwd-file="$cwd_file"
          local cwd
          cwd="$(cat "$cwd_file" 2>/dev/null || true)"
          rm -f "$cwd_file"
          if [[ -n "$cwd" && "$cwd" != "$PWD" ]]; then
            cd "$cwd" || return
          fi
        }
      '');

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
        (lib.mkIf ghDashEnabled {
          "gh-dash/config.yml".text = ''
            prSections:
              - title: My Pull Requests
                filters: is:open author:@me
              - title: Needs My Review
                filters: is:open review-requested:@me
              - title: Involved
                filters: is:open involves:@me -author:@me
            issuesSections:
              - title: Assigned
                filters: is:open assignee:@me
              - title: Mentioned
                filters: is:open mentions:@me
              - title: Involved
                filters: is:open involves:@me -assignee:@me
            defaults:
              view: prs
              refetchIntervalMinutes: 10
              layout:
                prs:
                  repo:
                    grow: true
                    width: 24
                  author:
                    width: 18
                  updatedAt:
                    width: 12
                issues:
                  repo:
                    grow: true
                    width: 24
                  author:
                    width: 18
                  updatedAt:
                    width: 12
              preview:
                open: true
                width: 84
            pager:
              diff: delta
            repoPaths: {}
          '';
        })
        (lib.mkIf k9sEnabled {
          "k9s/config.yaml".text = ''
            k9s:
              refreshRate: 2
              maxConnRetry: 5
              readOnly: false
              ui:
                enableMouse: true
                headless: false
                logoless: true
                crumbsless: false
                reactive: true
                noIcons: false
                skin: catppuccin-mocha
              logger:
                tail: 200
                buffer: 5000
                sinceSeconds: 300
                textWrap: false
          '';
          "k9s/aliases.yaml".text = ''
            aliases:
              po: v1/pods
              dp: apps/v1/deployments
              svc: v1/services
              ing: networking.k8s.io/v1/ingresses
          '';
          "k9s/hotkeys.yaml".text = ''
            hotKeys:
              shift-0:
                shortCut: Shift-0
                description: Pods
                command: pods
              shift-1:
                shortCut: Shift-1
                description: Deployments
                command: deployments
              shift-2:
                shortCut: Shift-2
                description: Services
                command: services
              shift-3:
                shortCut: Shift-3
                description: Ingresses
                command: ingresses
              shift-4:
                shortCut: Shift-4
                description: Contexts
                command: contexts
          '';
          "k9s/skins/catppuccin-mocha.yaml".text = ''
            k9s:
              body:
                fgColor: "#cdd6f4"
                bgColor: "#1e1e2e"
                logoColor: "#cba6f7"
              prompt:
                fgColor: "#cdd6f4"
                bgColor: "#313244"
                suggestColor: "#89b4fa"
              info:
                fgColor: "#89b4fa"
                sectionColor: "#cba6f7"
              dialog:
                fgColor: "#cdd6f4"
                bgColor: "#1e1e2e"
                buttonFgColor: "#cdd6f4"
                buttonBgColor: "#313244"
                buttonFocusFgColor: "#1e1e2e"
                buttonFocusBgColor: "#a6e3a1"
                labelFgColor: "#f9e2af"
                fieldFgColor: "#89b4fa"
              frame:
                border:
                  fgColor: "#6c7086"
                  focusColor: "#89b4fa"
                menu:
                  fgColor: "#cdd6f4"
                  keyColor: "#f9e2af"
                  numKeyColor: "#f38ba8"
                crumbs:
                  fgColor: "#1e1e2e"
                  bgColor: "#89b4fa"
                  activeColor: "#cba6f7"
                status:
                  newColor: "#89b4fa"
                  modifyColor: "#fab387"
                  addColor: "#a6e3a1"
                  errorColor: "#f38ba8"
                  highlightColor: "#f9e2af"
                  killColor: "#f38ba8"
                  completedColor: "#6c7086"
              views:
                table:
                  fgColor: "#cdd6f4"
                  bgColor: "#1e1e2e"
                  cursorFgColor: "#1e1e2e"
                  cursorBgColor: "#89b4fa"
                  markColor: "#f5c2e7"
                  header:
                    fgColor: "#a6e3a1"
                    bgColor: "#1e1e2e"
                    sorterColor: "#f9e2af"
                xray:
                  fgColor: "#cdd6f4"
                  bgColor: "#1e1e2e"
                  cursorColor: "#89b4fa"
                  graphicColor: "#cba6f7"
                yaml:
                  keyColor: "#89b4fa"
                  colonColor: "#6c7086"
                  valueColor: "#cdd6f4"
                logs:
                  fgColor: "#cdd6f4"
                  bgColor: "#1e1e2e"
                  indicator:
                    fgColor: "#f9e2af"
                    bgColor: "#1e1e2e"
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
        (lib.mkIf televisionEnabled {
          "television/config.toml".text = ''
            tick_rate = 50
            default_channel = "files"
            history_size = 500
            global_history = true

            [ui]
            theme = "catppuccin"
            orientation = "landscape"

            [ui.input_bar]
            prompt = "> "
            border_type = "rounded"

            [ui.results_panel]
            border_type = "rounded"

            [ui.preview_panel]
            size = 60
            scrollbar = true
            border_type = "rounded"

            [ui.help_panel]
            hidden = true

            [ui.remote_control]
            sort_alphabetically = true

            [shell_integration]
            fallback_channel = "files"

            [shell_integration.channel_triggers]
            dirs = ["cd", "ls", "rmdir"]
            files = ["cat", "less", "vim", "nvim", "code", "open"]
            "git-branches" = ["git checkout", "git switch", "git branch"]
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
        (lib.mkIf yaziEnabled {
          "yazi/yazi.toml".text = ''
            [mgr]
            show_hidden = true
            sort_by = "natural"
            sort_sensitive = false
            sort_dir_first = true
            linemode = "size"
            scrolloff = 8

            [preview]
            tab_size = 2
            max_width = 1200
            max_height = 1800

            [opener]
            edit = [
              { run = 'nvim "$@"', desc = "Edit", block = true, for = "unix" },
            ]
            reveal = [
              { run = 'open -R "$1"', desc = "Reveal", for = "macos" },
            ]

            [open]
            prepend_rules = [
              { mime = "text/*", use = "edit" },
              { mime = "application/json", use = "edit" },
            ]
          '';
          "yazi/keymap.toml".text = ''
            [mgr]
            prepend_keymap = [
              { on = [ "g", "d" ], run = "cd ~/Downloads", desc = "Go to Downloads" },
              { on = [ "g", "c" ], run = "cd ~/.config", desc = "Go to config" },
              { on = [ "!" ], run = 'shell "$SHELL" --block', desc = "Open shell here" },
            ]
          '';
        })
        (lib.mkIf zellijEnabled {
          "zellij/config.kdl".text = ''
            theme "catppuccin-mocha"
            default_layout "compact"
            pane_frames false
            simplified_ui true
            mouse_mode true
            copy_on_select true
            copy_command "pbcopy"
            scroll_buffer_size 10000
            scrollback_editor "nvim"
            show_startup_tips false
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

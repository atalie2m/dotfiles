{ inputs, nixLib, repoPaths }:

let
  treefmtConfigFor = pkgs: {
    projectRootFile = "flake.nix";
    settings = {
      global.excludes = [ ".direnv/**" "result/**" "flake.lock" ];
      formatter.prettier-json = {
        command = "${pkgs.prettier}/bin/prettier";
        includes = [ "*.json" "**/*.json" ];
        options = [ "--write" ];
      };
    };
    programs.nixpkgs-fmt.enable = true;
    programs.shfmt = {
      enable = true;
      indent_size = 2;
    };
  };

  mkDotfilesCliPackage = pkgs:
    pkgs.callPackage ../pkgs/dotfiles-cli { };

  mkSyncVscodeRustPackage = pkgs:
    pkgs.callPackage ../pkgs/dotfiles-sync-vscode { };

  mkDotfilesPackage = { pkgs, dotfilesCli, syncVscodeRust }:
    pkgs.writeShellScriptBin "dotfiles" ''
      export DOTFILES_ROOT="''${DOTFILES_ROOT:-${repoPaths.root}}"
      export DOTFILES_SYNC_VSCODE_BIN="''${DOTFILES_SYNC_VSCODE_BIN:-${syncVscodeRust}/bin/dotfiles-sync-vscode}"
      exec "${dotfilesCli}/bin/dotfiles" "$@"
    '';

  mkEditorSyncAppProgram = { pkgs, dotfilesPackage }:
    pkgs.writeShellScript "dotfiles-sync" ''
      set -uo pipefail

      if [[ -z "''${DOTFILES_ROOT:-}" ]]; then
        pwd_root="$(pwd)"
        if [[ -f "$pwd_root/flake.nix" && -d "$pwd_root/scripts" ]]; then
          export DOTFILES_ROOT="$pwd_root"
        fi
      fi
      if [[ -z "''${DOTFILES_ROOT:-}" ]] && command -v git >/dev/null 2>&1; then
        candidate_root="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
        if [[ -n "$candidate_root" && -f "$candidate_root/flake.nix" && -d "$candidate_root/scripts" ]]; then
          export DOTFILES_ROOT="$candidate_root"
        fi
      fi
      export DOTFILES_ROOT="''${DOTFILES_ROOT:-${repoPaths.root}}"

      status=0
      run_surface() {
        local surface="$1"
        shift
        printf 'dotfiles: running sync %s\n' "$surface" >&2
        "${dotfilesPackage}/bin/dotfiles" sync "$surface" "$@"
      }

      run_and_remember_status() {
        local surface="$1"
        shift
        run_surface "$surface" "$@" || {
          local command_status=$?
          if [[ "$status" -eq 0 ]]; then status=$command_status; fi
        }
      }

      if [[ "$#" -eq 0 ]]; then
        run_and_remember_status emacs --apply
        run_and_remember_status neovim --apply
      else
        run_and_remember_status emacs "$@"
        run_and_remember_status neovim "$@"
      fi

      exit "$status"
    '';

  mkPortableChecks = { pkgs, formatterWrapper, dotfilesPackage, syncVscodeRust, editorSyncAppProgram, vscodeZshLauncher }:
    {
      treefmt = pkgs.runCommand "treefmt-check"
        {
          nativeBuildInputs = [ pkgs.git formatterWrapper ];
          src = repoPaths.root;
        } ''
                      set -euo pipefail
                      project_dir="$TMPDIR/project"
                      cp -r "$src" "$project_dir"
                      chmod -R u+w "$project_dir"
                      cd "$project_dir"

                      export HOME="$TMPDIR/home"
                      mkdir -p "$HOME"
                      cat >"$HOME/.gitconfig" <<'GITCONFIG'
        [user]
          name = Nix
          email = nix@localhost
        [init]
          defaultBranch = main
        GITCONFIG
                      export GIT_CONFIG_NOSYSTEM=1
                      export LANG=en_US.UTF-8
                      export LC_ALL=en_US.UTF-8

        git init --quiet
        git add .
        git -c commit.gpgSign=false commit -m init --quiet

                      treefmt --version
                      treefmt --no-cache
                      git --no-pager diff --exit-code
                      touch "$out"
      '';

      statix = pkgs.runCommand "statix-check"
        {
          nativeBuildInputs = [ pkgs.statix ];
          src = repoPaths.root;
        } ''
                    cd "$src"
                    config_file=$(mktemp)
                    cat >"$config_file" <<'STATIX'
        disabled = [
          "manual_inherit",
          "manual_inherit_from",
          "useless_parens",
          "empty_pattern",
          "useless_has_attr",
          "repeated_keys",
        ]
        ignore = [ ".direnv", "result" ]
        nix_version = "2.4"
        STATIX
                    statix check --config "$config_file" .
                    touch "$out"
      '';

      deadnix = pkgs.runCommand "deadnix-check"
        {
          nativeBuildInputs = [ pkgs.deadnix ];
          src = repoPaths.root;
        } ''
        cd "$src"
        deadnix --fail -l -L .
        touch "$out"
      '';

      cargoWorkspaceTests = pkgs.rustPlatform.buildRustPackage {
        pname = "cargo-workspace-tests";
        version = "0.1.0";

        src = repoPaths.root;

        cargoLock = {
          lockFile = "${repoPaths.root}/Cargo.lock";
        };

        cargoBuildFlags = [ "--workspace" ];
        cargoTestFlags = [ "--workspace" ];

        doCheck = true;

        installPhase = ''
          mkdir -p "$out"
        '';
      };

      shellcheck = pkgs.runCommand "shellcheck-check"
        {
          nativeBuildInputs = [ pkgs.findutils pkgs.shellcheck ];
          src = repoPaths.root;
        } ''
        cd "$src"
        mapfile -t script_files < <(find scripts -type f -name '*.sh' | sort)
        mapfile -t sourced_files < <(
          {
            if [[ -d surfaces/shell/desired ]]; then
              find surfaces/shell/desired -type f -name '*.sh'
            fi
            if [[ -d apps/shell ]]; then
              find apps/shell -type f -name '*.sh'
            fi
          } | sort
        )

        if [[ "''${#script_files[@]}" -eq 0 && "''${#sourced_files[@]}" -eq 0 ]]; then
          touch "$out"
          exit 0
        fi

        if [[ "''${#script_files[@]}" -gt 0 ]]; then
          shellcheck \
            -e SC1091 \
            -e SC2016 \
            -e SC2129 \
            "''${script_files[@]}"
        fi

        if [[ "''${#sourced_files[@]}" -gt 0 ]]; then
          shellcheck \
            --shell=bash \
            -e SC1091 \
            -e SC2016 \
            -e SC2129 \
            "''${sourced_files[@]}"
        fi
        touch "$out"
      '';

      syncShellSmoke = pkgs.runCommand "sync-shell-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/sync-shell-smoke-test.sh
        touch "$out"
      '';

      shellCommonProfile = pkgs.runCommand "shell-common-profile-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.zsh ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/shell-common-profile-test.sh
        touch "$out"
      '';

      atuinContextHistory = pkgs.runCommand "atuin-context-history-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.zsh ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/atuin-context-history-test.sh
        touch "$out"
      '';

      terminalUx = pkgs.runCommand "terminal-ux-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.gnugrep pkgs.zsh ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/terminal-ux-test.sh
        touch "$out"
      '';

      syncCliCommonParse = pkgs.runCommand "sync-cli-common-parse-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/sync-cli-common-parse-test.sh
        touch "$out"
      '';

      syncEmacsSmoke = pkgs.runCommand "sync-emacs-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gnugrep dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/sync-emacs-smoke-test.sh
        touch "$out"
      '';

      emacsPlusNativeCompEnvSmoke = pkgs.runCommand "emacs-plus-native-comp-env-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/emacs-plus-native-comp-env-smoke-test.sh
        touch "$out"
      '';

      matrixToolsSmoke = pkgs.runCommand "matrix-tools-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/matrix-tools-smoke-test.sh
        touch "$out"
      '';

      exportCleanSmoke = pkgs.runCommand "export-clean-smoke-test"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils
            pkgs.git
            pkgs.gnused
            pkgs.gnutar
            dotfilesPackage
          ];
          src = repoPaths.root;
        } ''
                project_dir="$TMPDIR/project"
                cp -r "$src" "$project_dir"
                chmod -R u+w "$project_dir"
                rm -rf "$project_dir/.git"
                cd "$project_dir"
                export HOME="$TMPDIR/home"
                mkdir -p "$HOME"
                cat >"$HOME/.gitconfig" <<'GITCONFIG'
        [user]
          name = Nix
          email = nix@localhost
        [init]
          defaultBranch = main
        [safe]
          directory = *
        GITCONFIG
                export GIT_CONFIG_NOSYSTEM=1
                git init --quiet
                git add -A .
                export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
                export DOTFILES_ROOT="$project_dir"
                bash scripts/tests/export-clean-smoke-test.sh
                touch "$out"
      '';

      shellEntrypointWriteability = pkgs.runCommand "shell-zsh-writeability-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/shell-zsh-writeability-test.sh
        touch "$out"
      '';

      syncVscodeSmoke = pkgs.runCommand "sync-vscode-smoke-test"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.jq
            pkgs.sqlite
            dotfilesPackage
            syncVscodeRust
          ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        export DOTFILES_SYNC_VSCODE_BIN="${syncVscodeRust}/bin/dotfiles-sync-vscode"
        bash scripts/tests/sync-vscode-smoke-test.sh
        touch "$out"
      '';

      vscodeZshLauncherSmoke = pkgs.runCommand "vscode-zsh-launcher-smoke-test"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.gnugrep
            vscodeZshLauncher
          ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_VSCODE_ZSH_LAUNCHER="${vscodeZshLauncher}/bin/dotfiles-vscode-zsh"
        bash scripts/tests/vscode-zsh-launcher-test.sh
        touch "$out"
      '';

      syncNeovimSmoke = pkgs.runCommand "sync-neovim-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gnugrep dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/sync-neovim-smoke-test.sh
        touch "$out"
      '';

      syncEditorAppSmoke = pkgs.runCommand "sync-editor-app-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.diffutils pkgs.gnugrep dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        export DOTFILES_SYNC_APP="${editorSyncAppProgram}"
        bash scripts/tests/sync-editor-app-smoke-test.sh
        touch "$out"
      '';

      retiredHostLiterals = pkgs.runCommand "retired-host-literals-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.ripgrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/retired-host-literals-test.sh
        touch "$out"
      '';

      karabinerCuratedRules = pkgs.runCommand "karabiner-curated-rules-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.jq pkgs.ripgrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/karabiner-curated-rules-test.sh
        touch "$out"
      '';

      workflowContract = pkgs.runCommand "workflow-contract-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.gnugrep pkgs.gawk ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/workflow-contract-test.sh
        touch "$out"
      '';

      shimDelegation = pkgs.runCommand "shim-delegation-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.gnugrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/shim-delegation-test.sh
        touch "$out"
      '';

      agentNotifications = pkgs.runCommand "agent-notifications-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.python3 dotfilesPackage ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_BIN="${dotfilesPackage}/bin/dotfiles"
        export DOTFILES_ROOT="$src"
        bash scripts/tests/codex-slack-notification-test.sh
        touch "$out"
      '';
    }
    // {
      docsConsistency = pkgs.runCommand "docs-consistency-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.gnugrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/docs-consistency-test.sh
        touch "$out"
      '';

      hostTruth = pkgs.runCommand "host-truth-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.ripgrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/host-truth-test.sh
        touch "$out"
      '';
    };

  mkPortableDevShell = { pkgs, formatterWrapper }:
    pkgs.mkShell {
      name = "dotfiles-dev";
      packages = [
        pkgs.zsh
        pkgs.age
        pkgs.deadnix
        pkgs.nvfetcher
        pkgs.shellcheck
        pkgs.sops
        pkgs.statix
        formatterWrapper
      ];
      shellHook = ''
        if [[ -z "''${ZSH_VERSION:-}" && -t 0 && -t 1 ]]; then
          if [[ -f "$HOME/.nix/.zshrc" ]]; then
            export ZDOTDIR="$HOME/.nix"
          fi
          exec ${pkgs.zsh}/bin/zsh -i
        fi
      '';
    };

in
{
  inherit
    treefmtConfigFor
    mkDotfilesCliPackage
    mkDotfilesPackage
    mkEditorSyncAppProgram
    mkSyncVscodeRustPackage
    mkPortableChecks
    mkPortableDevShell
    ;
}

{ inputs, nixLib, repoPaths }:

let
  linuxSystems = [ "aarch64-linux" "x86_64-linux" ];

  treefmtConfigFor = pkgs: {
    projectRootFile = "flake.nix";
    settings = {
      global.excludes = [ ".direnv/**" "result/**" "flake.lock" ];
      formatter.prettier-json = {
        command = "${pkgs.nodePackages.prettier}/bin/prettier";
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

  mkSyncVscodeRustPackage = pkgs:
    pkgs.callPackage ../pkgs/dotfiles-sync-vscode { };

  mkPortableChecks = { pkgs, formatterWrapper, syncVscodeRust }:
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
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/sync-shell-smoke-test.sh
        touch "$out"
      '';

      syncCliMigration = pkgs.runCommand "sync-cli-migration-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.git ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/sync-cli-migration-test.sh
        touch "$out"
      '';

      syncCliCommonParse = pkgs.runCommand "sync-cli-common-parse-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/sync-cli-common-parse-test.sh
        touch "$out"
      '';

      matrixToolsSmoke = pkgs.runCommand "matrix-tools-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/matrix-tools-smoke-test.sh
        touch "$out"
      '';

      exportCleanSmoke = pkgs.runCommand "export-clean-smoke-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.coreutils pkgs.git pkgs.gnused pkgs.gnutar ];
          src = repoPaths.root;
        } ''
        project_dir="$TMPDIR/project"
        cp -r "$src" "$project_dir"
        chmod -R u+w "$project_dir"
        cd "$project_dir"
        git init --quiet
        git add .
        bash scripts/tests/export-clean-smoke-test.sh
        touch "$out"
      '';

      shellEntrypointWriteability = pkgs.runCommand "shell-zsh-writeability-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/shell-zsh-writeability-test.sh
        touch "$out"
      '';

      zshrcCompat = pkgs.runCommand "zshrc-compat-test"
        {
          nativeBuildInputs = [ pkgs.bash pkgs.diffutils pkgs.gawk pkgs.gnugrep ];
          src = repoPaths.root;
        } ''
        cd "$src"
        bash scripts/tests/zshrc-compat-test.sh
        touch "$out"
      '';

      syncVscodeSmoke = pkgs.runCommand "sync-vscode-smoke-test"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.jq
            pkgs.sqlite
            syncVscodeRust
          ];
          src = repoPaths.root;
        } ''
        cd "$src"
        export DOTFILES_SYNC_VSCODE_BIN="${syncVscodeRust}/bin/dotfiles-sync-vscode"
        bash scripts/tests/sync-vscode-smoke-test.sh
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

  linuxContributorOutputs =
    nixLib.foldl'
      nixLib.recursiveUpdate
      { }
      (map
        (system:
          let
            pkgs = import inputs.nixpkgs-linux { inherit system; };
            treefmtEval = inputs.treefmt-nix.lib.evalModule pkgs (treefmtConfigFor pkgs);
            formatterWrapper = treefmtEval.config.build.wrapper;
            syncVscodeRust = mkSyncVscodeRustPackage pkgs;
          in
          {
            formatter.${system} = formatterWrapper;
            checks.${system} = mkPortableChecks {
              inherit pkgs formatterWrapper syncVscodeRust;
            };
            devShells.${system}.default = mkPortableDevShell { inherit pkgs formatterWrapper; };
            packages.${system}.dotfiles-sync-vscode = syncVscodeRust;
            apps.${system}.format = {
              type = "app";
              program = "${pkgs.writeShellScript "dotfiles-format" ''
                exec ${formatterWrapper}/bin/treefmt "$@"
              ''}";
              meta.description = "Format Nix and shell files with treefmt.";
            };
          })
        linuxSystems);
in
{
  inherit
    treefmtConfigFor
    mkSyncVscodeRustPackage
    mkPortableChecks
    mkPortableDevShell
    linuxContributorOutputs
    ;
}

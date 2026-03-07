{ delib, lib, repoPaths, ... }:

# Optional ~/.zshrc compat symlink for installers that append to the root entrypoint.

delib.module {
  name = "tools.shell.zsh.rootZshrcCompat";

  options = with delib; moduleOptions {
    enable = boolOption false;
  };

  darwin.ifEnabled = { myconfig, ... }:
    let
      compatScript = "${repoPaths.scripts}/zshrc-compat.sh";
      zshEnabled = ((((myconfig.tools or { }).shell or { }).zsh or { }).enable or false);
    in
    {
      assertions = [
        {
          assertion = zshEnabled;
          message = "tools.shell.zsh.rootZshrcCompat.enable requires tools.shell.zsh.enable = true.";
        }
      ];

      home-manager.sharedModules = [
        ({ ... }: {
          home.activation.ensureRootZshrcCompat = lib.mkOrder 910 ''
            bash ${compatScript} --apply
          '';
        })
      ];
    };
}

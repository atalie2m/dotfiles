{ dotmod, config, lib, pkgs, ... }:

# Headroom context-compression wrapper for coding agents.

(dotmod.mkModule { inherit config; }) {
  path = "tools.aiCodingAgent.headroom";

  options = with dotmod; moduleOptions {
    enable = boolOption false;
    packageSpec = strOption "headroom-ai[proxy,code,mcp]";
  };

  homeOnEnable = { cfg, ... }:
    let
      python = pkgs.python313;
      uv = lib.getExe pkgs.uv;
      packageSpec = lib.escapeShellArg cfg.packageSpec;

      mkHeadroomWrapper = name: args:
        let
          fixedArgs = lib.concatMapStringsSep " " lib.escapeShellArg args;
        in
        pkgs.writeShellApplication {
          inherit name;
          text = ''
            export HEADROOM_TELEMETRY=off
            exec ${uv} tool run --python ${python.interpreter} --from ${packageSpec} headroom ${fixedArgs} "$@"
          '';
        };
    in
    {
      home.packages = [
        (mkHeadroomWrapper "headroom" [ ])
        (mkHeadroomWrapper "headroom-codex" [ "wrap" "codex" ])
        (mkHeadroomWrapper "headroom-claude" [ "wrap" "claude" ])
      ];

      home.sessionVariables.HEADROOM_TELEMETRY = lib.mkDefault "off";
    };
}

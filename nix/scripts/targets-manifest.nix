{ }:

let
  catalog = import ../denix/darwin/host-catalog.nix;
  hostSpecs = catalog.hosts;

  targetHostName = targetName: cfg:
    if cfg ? myconfig && cfg.myconfig ? hostContext && cfg.myconfig.hostContext ? name then
      cfg.myconfig.hostContext.name
    else
      throw "target '${targetName}' is missing config.myconfig.hostContext.name";

  targetRiceName = targetName: cfg:
    if cfg ? myconfig && cfg.myconfig ? rice && cfg.myconfig.rice ? name then
      cfg.myconfig.rice.name
    else
      throw "target '${targetName}' is missing config.myconfig.rice.name";

  targetEntries = targets:
    map
      (targetName:
        let
          cfg = targets.${targetName}.config;
        in
        {
          name = targetName;
          host = targetHostName targetName cfg;
          rice = targetRiceName targetName cfg;
        })
      (builtins.attrNames targets);

  uniqueTargetFor = entries: hostName: riceName:
    let
      matches = builtins.filter (entry: entry.host == hostName && entry.rice == riceName) entries;
      explicitTarget = "${hostName}-${riceName}";
      explicitMatches = builtins.filter (entry: entry.name == explicitTarget) matches;
    in
    if builtins.length explicitMatches == 1 then
      explicitTarget
    else if builtins.length matches != 1 then
      throw "expected exactly one target for host '${hostName}' and rice '${riceName}'"
    else
      (builtins.head matches).name;

  validateBuildTarget = entries: hostName: hostSpec:
    let
      matches = builtins.filter (entry: entry.name == hostSpec.buildTarget) entries;
    in
    if builtins.length matches != 1 then
      throw "buildTarget '${hostSpec.buildTarget}' is not present for host '${hostName}'"
    else
      let
        match = builtins.head matches;
        _ =
          if match.host != hostName then
            throw "buildTarget '${hostSpec.buildTarget}' resolved to host '${match.host}', expected '${hostName}'"
          else if match.rice != hostSpec.defaultRice then
            throw "buildTarget '${hostSpec.buildTarget}' resolved to rice '${match.rice}', expected default rice '${hostSpec.defaultRice}'"
          else
            null;
      in
      builtins.seq _ hostSpec.buildTarget;

  manifestFor = targets:
    let
      entries = targetEntries targets;
    in
    {
      hosts =
        builtins.mapAttrs
          (hostName: hostSpec:
            let
              targetsByRice =
                builtins.listToAttrs
                  (map
                    (riceName: {
                      name = riceName;
                      value = uniqueTargetFor entries hostName riceName;
                    })
                    hostSpec.supportedRices);
            in
            {
              defaultRice = hostSpec.defaultRice;
              buildTarget = validateBuildTarget entries hostName hostSpec;
              supportedRices = hostSpec.supportedRices;
              machineKey = hostSpec.machineKey;
              system = hostSpec.system;
              inherit targetsByRice;
            })
          hostSpecs;
    };
in
{
  json = manifestFor;
}

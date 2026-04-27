{}:

let
  catalog = import ../catalog/darwin/hosts.nix;
  hostSpecs = catalog.hosts;

  targetHostName =
    targetName: cfg:
    if cfg ? myconfig && cfg.myconfig ? hostContext && cfg.myconfig.hostContext ? name then
      cfg.myconfig.hostContext.name
    else
      throw "target '${targetName}' is missing config.myconfig.hostContext.name";

  targetProfileName =
    targetName: cfg:
    if cfg ? myconfig && cfg.myconfig ? profile && cfg.myconfig.profile ? name then
      cfg.myconfig.profile.name
    else
      throw "target '${targetName}' is missing config.myconfig.profile.name";

  targetEntries =
    targets:
    map
      (
        targetName:
        let
          cfg = targets.${targetName}.config;
        in
        {
          name = targetName;
          host = targetHostName targetName cfg;
          profile = targetProfileName targetName cfg;
        }
      )
      (builtins.attrNames targets);

  uniqueTargetFor =
    entries: hostName: profileName:
    let
      matches = builtins.filter (entry: entry.host == hostName && entry.profile == profileName) entries;
      explicitTarget = "${hostName}-${profileName}";
      explicitMatches = builtins.filter (entry: entry.name == explicitTarget) matches;
    in
    if builtins.length explicitMatches == 1 then
      explicitTarget
    else if builtins.length matches != 1 then
      throw "expected exactly one target for host '${hostName}' and profile '${profileName}'"
    else
      (builtins.head matches).name;

  validateBuildTarget =
    entries: hostName: hostSpec:
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
          else if match.profile != hostSpec.defaultProfile then
            throw "buildTarget '${hostSpec.buildTarget}' resolved to profile '${match.profile}', expected default profile '${hostSpec.defaultProfile}'"
          else
            null;
      in
      builtins.seq _ hostSpec.buildTarget;

  sortedStrings = values: builtins.sort builtins.lessThan values;

  manifestTargetNames =
    hosts:
    sortedStrings (
      builtins.attrNames (
        builtins.listToAttrs (
          builtins.concatLists (
            map
              (
                hostName:
                let
                  hostManifest = hosts.${hostName};
                in
                [
                  {
                    name = hostManifest.buildTarget;
                    value = true;
                  }
                ]
                ++ (map
                  (targetName: {
                    name = targetName;
                    value = true;
                  })
                  (builtins.attrValues hostManifest.targetsByProfile))
              )
              (builtins.attrNames hosts)
          )
        )
      )
    );

  manifestFor =
    targets:
    let
      entries = targetEntries targets;
      hosts = builtins.mapAttrs
        (
          hostName: hostSpec:
            let
              targetsByProfile = builtins.listToAttrs (
                map
                  (profileName: {
                    name = profileName;
                    value = uniqueTargetFor entries hostName profileName;
                  })
                  hostSpec.supportedProfiles
              );
              buildTarget = validateBuildTarget entries hostName hostSpec;
              _defaultProfileTargetCheck =
                let
                  defaultTarget =
                    if builtins.hasAttr hostSpec.defaultProfile targetsByProfile then
                      targetsByProfile.${hostSpec.defaultProfile}
                    else
                      throw "host '${hostName}' defaultProfile '${hostSpec.defaultProfile}' is missing from targetsByProfile";
                in
                if defaultTarget != buildTarget then
                  throw "host '${hostName}' default profile target '${defaultTarget}' must equal buildTarget '${buildTarget}'"
                else
                  null;
            in
            builtins.seq _defaultProfileTargetCheck {
              defaultProfile = hostSpec.defaultProfile;
              inherit buildTarget;
              supportedProfiles = hostSpec.supportedProfiles;
              machineKey = hostSpec.machineKey;
              system = hostSpec.system;
              inherit targetsByProfile;
            }
        )
        hostSpecs;
      actualTargets = sortedStrings (builtins.attrNames targets);
      declaredTargets = manifestTargetNames hosts;
      _targetSetCheck =
        if declaredTargets != actualTargets then
          throw "targets manifest does not exactly match darwinConfigurations (declared=${builtins.toJSON declaredTargets}, actual=${builtins.toJSON actualTargets})"
        else
          null;
    in
    builtins.seq _targetSetCheck {
      inherit hosts;
    };
in
{
  json = manifestFor;
}

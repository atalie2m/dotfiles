{ lib }:

let
  merge = builtins.foldl' lib.recursiveUpdate { };

  splitPath = path: lib.splitString "." path;

  isOverrideMarker = value:
    builtins.isAttrs value && value ? _type;

  isEnablePath = path:
    lib.hasSuffix ".enable" path;

  isTrueEnable = entry:
    entry.value;

  pathGroup = path:
    builtins.head (splitPath path);

  hasPathPrefix = prefix: path:
    path == prefix || lib.hasPrefix "${prefix}." path;

  flattenEnableToggles = prefix: value:
    if builtins.isAttrs value && !isOverrideMarker value then
      builtins.concatLists
        (
          builtins.map
            (name:
              flattenEnableToggles
                (if prefix == "" then name else "${prefix}.${name}")
                value.${name})
            (builtins.attrNames value)
        )
    else if builtins.isBool value && isEnablePath prefix then
      [
        {
          path = prefix;
          value = value;
        }
      ]
    else
      [ ];

  candidateTools = profileMyconfig: hostExtraMyconfig:
    (lib.recursiveUpdate profileMyconfig hostExtraMyconfig).tools or { };

  forceOffAt = path:
    lib.setAttrByPath (splitPath path) (lib.mkForce false);

  denySpecMatches = spec: path:
    let
      wildcard = lib.removeSuffix ".*" spec;
      parts = splitPath spec;
      toolPrefix =
        if builtins.length parts >= 2 then
          "${builtins.elemAt parts 0}.${builtins.elemAt parts 1}"
        else
          spec;
    in
    if lib.hasSuffix ".*" spec then
      path == "${wildcard}.enable" || hasPathPrefix "${wildcard}." path
    else
      path == "${toolPrefix}.enable" || hasPathPrefix "${toolPrefix}." path;

  deniedPathsFor = trueEntries: deniedTools:
    builtins.concatLists (
      builtins.map
        (spec:
          let
            parts = splitPath spec;
            explicitPath =
              if lib.hasSuffix ".*" spec then
                "${lib.removeSuffix ".*" spec}.enable"
              else if builtins.length parts == 2 then
                "${spec}.enable"
              else
                spec;
            matchingPaths =
              builtins.map
                (entry: entry.path)
                (builtins.filter (entry: denySpecMatches spec entry.path) trueEntries);
          in
          [ explicitPath ] ++ matchingPaths)
        deniedTools
    );

  outsideAllowedPathsFor = trueEntries: allowedGroups:
    builtins.map
      (entry: entry.path)
      (builtins.filter
        (entry: !(builtins.elem (pathGroup entry.path) allowedGroups))
        trueEntries);

  unique = values:
    builtins.attrNames (
      builtins.listToAttrs (
        builtins.map (value: { name = value; value = true; }) values
      )
    );
in
{
  forcedOverridesFor = { profileMyconfig, hostExtraMyconfig ? { }, policy }:
    let
      trueEntries =
        builtins.filter isTrueEnable (
          flattenEnableToggles "" (candidateTools profileMyconfig hostExtraMyconfig)
        );
      forcedPaths = unique (
        outsideAllowedPathsFor trueEntries (policy.allowedGroups or [ ])
        ++ deniedPathsFor trueEntries (policy.deniedTools or [ ])
        ++ (policy.forcedOff or [ ])
      );
    in
    {
      tools = merge (builtins.map forceOffAt forcedPaths);
    };
}

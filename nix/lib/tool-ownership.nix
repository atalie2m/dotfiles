{ lib, nixCatalog, brewCatalog, dedicatedHomebrew ? { } }:

let
  enabledAt = optionPath: config:
    lib.attrByPath optionPath false config;

  homebrewClaimsFor = { key, brews ? [ ], casks ? [ ], masApps ? { } }:
    let
      brewClaims = map
        (itemName: {
          inherit key itemName;
          source = "homebrew";
          itemType = "brew";
        })
        brews;
      caskClaims = map
        (itemName: {
          inherit key itemName;
          source = "homebrew";
          itemType = "cask";
        })
        casks;
      masClaims = map
        (itemName: {
          inherit key itemName;
          source = "homebrew";
          itemType = "mas";
        })
        (builtins.attrNames masApps);
    in
    brewClaims ++ caskClaims ++ masClaims;

  nixClaimsFromCatalog = config:
    lib.concatMap
      (toolName:
        let
          spec = nixCatalog.${toolName};
          key = "${spec.group}.${toolName}";
        in
        if enabledAt [ "myconfig" "tools" spec.group toolName "enable" ] config
        then [{ inherit key; source = "nix"; }]
        else [ ])
      (builtins.attrNames nixCatalog);

  homebrewClaimsFromCatalog = config:
    lib.concatMap
      (toolName:
        let
          spec = brewCatalog.${toolName};
          key = "${spec.group}.${toolName}";
        in
        if enabledAt [ "myconfig" "tools" spec.group toolName "enable" ] config
        then
          homebrewClaimsFor
            {
              inherit key;
              brews = spec.brews or [ ];
              casks = spec.casks or [ ];
              masApps = spec.masApps or { };
            }
        else [ ])
      (builtins.attrNames brewCatalog);

  dedicatedHomebrewClaims = config:
    lib.concatMap
      (key:
        let
          spec = dedicatedHomebrew.${key};
        in
        if enabledAt spec.optionPath config
        then
          homebrewClaimsFor
            {
              inherit key;
              brews = spec.brews or [ ];
              casks = spec.casks or [ ];
              masApps = spec.masApps or { };
            }
        else [ ])
      (builtins.attrNames dedicatedHomebrew);

  registryFromClaims = claims:
    builtins.foldl'
      (acc: claim:
        let
          entry = lib.filterAttrs (_: value: value != "") {
            source = claim.source;
            itemType = claim.itemType or "";
            itemName = claim.itemName or "";
          };
          existing = acc.${claim.key} or [ ];
        in
        if (claim.key or "") == "" || (claim.source or "") == "" then acc else acc // {
          ${claim.key} = existing ++ [ entry ];
        })
      { }
      claims;

  flattenRegistry = registry:
    lib.concatMap
      (key:
        map
          (claim: claim // { inherit key; })
          (registry.${key} or [ ]))
      (builtins.attrNames registry);

  homebrewItems = homebrew:
    let
      mkItem = itemType: raw:
        let
          itemName =
            if builtins.isAttrs raw then raw.name or ""
            else raw;
        in
        {
          inherit itemType itemName;
        };
      brews = map (mkItem "brew") (homebrew.brews or [ ]);
      casks = map (mkItem "cask") (homebrew.casks or [ ]);
      masApps = map
        (itemName: {
          itemType = "mas";
          inherit itemName;
        })
        (builtins.attrNames (homebrew.masApps or { }));
    in
    lib.filter (item: item.itemName != "") (brews ++ casks ++ masApps);

  sourceSummary = claims:
    lib.unique (map (claim: claim.source or "") claims);
in
{
  registryFromConfig = config:
    registryFromClaims (
      nixClaimsFromCatalog config
      ++ homebrewClaimsFromCatalog config
      ++ dedicatedHomebrewClaims config
    );

  report = targetName: config:
    let
      registry = registryFromClaims (
        nixClaimsFromCatalog config
        ++ homebrewClaimsFromCatalog config
        ++ dedicatedHomebrewClaims config
      );
      registryClaims = flattenRegistry registry;
      duplicateClaims =
        lib.filter
          (entry: builtins.length (sourceSummary entry.claims) > 1)
          (map
            (key: {
              inherit key;
              claims = registry.${key};
            })
            (builtins.attrNames registry));
      claimedHomebrewItems =
        lib.unique
          (map
            (claim: "${claim.itemType}:${claim.itemName}")
            (lib.filter
              (claim:
                (claim.source or "") == "homebrew"
                && (claim.itemType or "") != ""
                && (claim.itemName or "") != "")
              registryClaims));
      unclaimedHomebrew =
        lib.filter
          (item: !lib.elem "${item.itemType}:${item.itemName}" claimedHomebrewItems)
          (homebrewItems (config.homebrew or { }));
      failureMessages =
        (map
          (entry:
            "${targetName}: duplicate ownership for ${entry.key} (${lib.concatStringsSep ", " (sourceSummary entry.claims)})")
          duplicateClaims)
        ++
        (map
          (item:
            "${targetName}: unregistered Homebrew ${item.itemType} '${item.itemName}' in final config")
          unclaimedHomebrew);
    in
    {
      inherit duplicateClaims failureMessages registry targetName unclaimedHomebrew;
      hasFailures = failureMessages != [ ];
    };
}

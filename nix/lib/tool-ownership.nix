{ lib, nixCatalog, brewCatalog, dedicatedHomebrew ? { } }:

let
  enabledAt = optionPath: config:
    lib.attrByPath optionPath false config;

  homebrewClaimsFor =
    { key
    , claimSource
    , brews ? [ ]
    , casks ? [ ]
    , masApps ? { }
    ,
    }:
    let
      brewClaims = map
        (itemName: {
          inherit key itemName;
          source = claimSource;
          itemType = "brew";
        })
        brews;
      caskClaims = map
        (itemName: {
          inherit key itemName;
          source = claimSource;
          itemType = "cask";
        })
        casks;
      masClaims = map
        (itemName: {
          inherit key itemName;
          source = claimSource;
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
        then [{ inherit key; source = "nixCatalog"; }]
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
              claimSource = "brewCatalog";
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
              claimSource = "dedicatedHomebrew";
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

  itemIdForClaim = claim:
    if (claim.itemType or "") != "" && (claim.itemName or "") != ""
    then "${claim.itemType}:${claim.itemName}"
    else "";

  itemRegistryFromClaims = claims:
    builtins.foldl'
      (acc: claim:
        let
          itemId = itemIdForClaim claim;
        in
        if itemId == "" then
          acc
        else
          let
            existing = acc.${itemId} or {
              itemType = claim.itemType;
              itemName = claim.itemName;
              owners = [ ];
            };
          in
          acc
          // {
            ${itemId} = existing // {
              owners = existing.owners ++ [{
                inherit (claim) key source;
              }];
            };
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

  claimsFromConfig = config:
    nixClaimsFromCatalog config
    ++ homebrewClaimsFromCatalog config
    ++ dedicatedHomebrewClaims config;

  sourceSummary = claims:
    lib.unique (map (claim: claim.source or "") claims);

  ownerSummary = owners:
    lib.unique (map (owner: owner.key or "") owners);
in
{
  registryFromConfig = config:
    registryFromClaims (claimsFromConfig config);

  report = targetName: config:
    let
      claims = claimsFromConfig config;
      registry = registryFromClaims claims;
      registryClaims = flattenRegistry registry;
      itemRegistry = itemRegistryFromClaims claims;
      duplicateClaims =
        lib.filter
          (entry: builtins.length (sourceSummary entry.claims) > 1)
          (map
            (key: {
              inherit key;
              claims = registry.${key};
            })
            (builtins.attrNames registry));
      duplicateHomebrewItems =
        lib.filter
          (entry: builtins.length (ownerSummary entry.owners) > 1)
          (map
            (itemId: (itemRegistry.${itemId}) // { inherit itemId; })
            (builtins.attrNames itemRegistry));
      claimedHomebrewItems =
        lib.unique
          (map
            itemIdForClaim
            (lib.filter (claim: itemIdForClaim claim != "") registryClaims));
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
          (entry:
            "${targetName}: duplicate Homebrew ${entry.itemType} '${entry.itemName}' claimed by ${lib.concatStringsSep ", " (ownerSummary entry.owners)}")
          duplicateHomebrewItems)
        ++
        (map
          (item:
            "${targetName}: unregistered Homebrew ${item.itemType} '${item.itemName}' in final config")
          unclaimedHomebrew);
    in
    {
      inherit duplicateClaims duplicateHomebrewItems failureMessages itemRegistry registry targetName unclaimedHomebrew;
      hasFailures = failureMessages != [ ];
    };
}

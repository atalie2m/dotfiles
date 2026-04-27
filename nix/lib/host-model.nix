let
  validKeyboardTypes = [ "ansi" "jis" ];

  defaultStateVersion = {
    home = "25.11";
    darwin = 6;
  };

  optionalNonEmptyString = value:
    if value == null then
      null
    else if builtins.isString value && value != "" then
      value
    else
      null;

  optionalAbsolutePath = value:
    let
      normalized = optionalNonEmptyString value;
    in
    if normalized != null && builtins.match "^/.+" normalized != null then normalized else null;

  stringList = value:
    if builtins.isList value then builtins.filter builtins.isString value else [ ];

  defaultMachine = {
    homeDirectory = null;
    computerName = null;
    localHostName = null;
    hostName = null;
    domain = null;
    keyboardType = null;
    extra = { };
  };

  normalizeMachine = raw:
    let
      machine = if builtins.isAttrs raw then raw else { };
    in
    {
      homeDirectory = optionalAbsolutePath (machine.homeDirectory or null);
      computerName = optionalNonEmptyString (machine.computerName or null);
      localHostName = optionalNonEmptyString (machine.localHostName or null);
      hostName = optionalNonEmptyString (machine.hostName or null);
      domain = optionalNonEmptyString (machine.domain or null);
      keyboardType =
        let
          value = machine.keyboardType or null;
        in
        if builtins.elem value validKeyboardTypes then value else null;
      extra =
        if machine ? extra && builtins.isAttrs machine.extra then
          machine.extra
        else
          { };
    };

  normalizeStateVersion = raw:
    let
      value = if builtins.isAttrs raw then raw else { };
    in
    if value ? nixos then
      throw "facts.user.stateVersion.nixos has been removed; delete it from facts.nix"
    else
      {
        home =
          if value ? home && builtins.isString value.home && value.home != "" then
            value.home
          else
            defaultStateVersion.home;
        darwin =
          if value ? darwin && builtins.isInt value.darwin then
            value.darwin
          else
            defaultStateVersion.darwin;
      };

  normalizeRawFacts = rawFacts:
    let
      facts = if builtins.isAttrs rawFacts then rawFacts else { };
      user = if facts ? user && builtins.isAttrs facts.user then facts.user else { };
      binaryCaches =
        if facts ? binaryCaches && builtins.isAttrs facts.binaryCaches then
          facts.binaryCaches
        else
          { };
    in
    {
      user = {
        username =
          if user ? username && builtins.isString user.username && user.username != "" then
            user.username
          else
            null;
        fullName = optionalNonEmptyString (user.fullName or null);
        email = optionalNonEmptyString (user.email or null);
        homeDirectory = optionalAbsolutePath (user.homeDirectory or null);
        configDirectory =
          if user ? configDirectory && builtins.isString user.configDirectory && user.configDirectory != "" then
            user.configDirectory
          else
            ".config";
        stateVersion = normalizeStateVersion (user.stateVersion or { });
      };
      machines =
        if facts ? machines && builtins.isAttrs facts.machines then
          builtins.mapAttrs (_: normalizeMachine) facts.machines
        else
          { };
      binaryCaches = {
        substituters = stringList (binaryCaches.substituters or [ ]);
        trustedPublicKeys = stringList (binaryCaches.trustedPublicKeys or [ ]);
      };
    };

  parseSystem = system:
    let
      match = builtins.match "^([^-]+)-([^-]+)$" system;
    in
    if match == null then
      throw "unsupported host system '${system}'"
    else
      {
        arch = builtins.elemAt match 0;
        os = builtins.elemAt match 1;
      };

  mkHomeDirectory = { os, username, rawUserHomeDirectory, machineHomeDirectory ? null }:
    let
      machineHome = optionalAbsolutePath machineHomeDirectory;
      userHome = optionalAbsolutePath rawUserHomeDirectory;
      defaultHome =
        if os == "darwin" then "/Users/${username}" else "/home/${username}";
    in
    if machineHome != null then machineHome else if userHome != null then userHome else defaultHome;

  buildHostModel = { name, machineKey, system, rawFacts }:
    let
      normalizedFacts = normalizeRawFacts rawFacts;
      parsedSystem = parseSystem system;
      machine = normalizedFacts.machines.${machineKey} or defaultMachine;
      username = normalizedFacts.user.username;
    in
    if username == null then
      throw "facts.user.username is required for ${name}"
    else
      let
        homeDirectory = mkHomeDirectory {
          os = parsedSystem.os;
          inherit username;
          rawUserHomeDirectory = normalizedFacts.user.homeDirectory;
          machineHomeDirectory = machine.homeDirectory;
        };
      in
      {
        inherit name machineKey system;
        os = parsedSystem.os;
        arch = parsedSystem.arch;
        user = normalizedFacts.user // {
          inherit homeDirectory;
        };
        inherit (normalizedFacts) binaryCaches machines;
        inherit machine;
      };

  rawFactsChecks = rawFacts:
    let
      facts = if builtins.isAttrs rawFacts then rawFacts else null;
      hasRoot = facts != null;
      user = if hasRoot && facts ? user && builtins.isAttrs facts.user then facts.user else null;
      hasUser = user != null;
      username = if hasUser && user ? username then user.username else null;
      homeDirectory = if hasUser && user ? homeDirectory then user.homeDirectory else null;
      machines = if hasRoot && facts ? machines then facts.machines else null;
      binaryCaches = if hasRoot && facts ? binaryCaches then facts.binaryCaches else null;
      substituters =
        if builtins.isAttrs binaryCaches && binaryCaches ? substituters then
          binaryCaches.substituters
        else
          null;
      trustedPublicKeys =
        if builtins.isAttrs binaryCaches && binaryCaches ? trustedPublicKeys then
          binaryCaches.trustedPublicKeys
        else
          null;
      stateVersion = if hasUser && user ? stateVersion then user.stateVersion else null;
      stateHome = if builtins.isAttrs stateVersion && stateVersion ? home then stateVersion.home else null;
      stateDarwin = if builtins.isAttrs stateVersion && stateVersion ? darwin then stateVersion.darwin else null;
      hasDeprecatedPlatform = hasUser && user ? platform;
      hasDeprecatedSystemType = hasUser && user ? systemType;
      hasDeprecatedArchitecture = hasUser && user ? architecture;
      mk = name: status: message: {
        inherit name status message;
      };
      optionalString = value: value == null || builtins.isString value;
      optionalAttrs = value: value == null || builtins.isAttrs value;
      optionalListOfStrings = value: value == null || (builtins.isList value && builtins.all builtins.isString value);
    in
    [
      (mk "facts.schema.root"
        (if hasRoot then "ok" else "fail")
        (if hasRoot then "facts is an attrset" else "facts.nix must return an attrset"))
      (mk "facts.schema.user"
        (if hasUser then "ok" else "fail")
        (if hasUser then "facts.user is an attrset" else "facts.user must be an attrset"))
      (mk "facts.username"
        (if builtins.isString username && username != "" then "ok" else "fail")
        (if builtins.isString username && username != "" then username else "facts.user.username must be a non-empty string"))
      (mk "facts.fullName"
        (if optionalString (if hasUser && user ? fullName then user.fullName else null) then "ok" else "fail")
        (if !hasUser || !(user ? fullName) then "facts.user.fullName not set (optional)"
        else if builtins.isString user.fullName then "facts.user.fullName set"
        else "facts.user.fullName must be a string"))
      (mk "facts.email"
        (if optionalString (if hasUser && user ? email then user.email else null) then "ok" else "fail")
        (if !hasUser || !(user ? email) then "facts.user.email not set (optional)"
        else if builtins.isString user.email then "facts.user.email set"
        else "facts.user.email must be a string"))
      (mk "facts.homeDirectory"
        (if optionalString homeDirectory then "ok" else "fail")
        (if homeDirectory == null then "facts.user.homeDirectory not set (auto-derived)"
        else if builtins.isString homeDirectory then homeDirectory
        else "facts.user.homeDirectory must be a string"))
      (mk "facts.homeDirectoryFormat"
        (if homeDirectory == null then "ok"
        else if !builtins.isString homeDirectory then "fail"
        else if builtins.match "^/.+" homeDirectory != null then "ok" else "warn")
        (if homeDirectory == null then "facts.user.homeDirectory not set (auto-derived)"
        else if !builtins.isString homeDirectory then "facts.user.homeDirectory must be a string"
        else if builtins.match "^/.+" homeDirectory != null then "facts.user.homeDirectory is absolute"
        else "facts.user.homeDirectory should be an absolute path"))
      (mk "facts.platform"
        (if hasDeprecatedPlatform then "fail" else "ok")
        (if hasDeprecatedPlatform then "facts.user.platform has been removed; host declarations now own system selection" else "facts.user.platform not set"))
      (mk "facts.systemType"
        (if hasDeprecatedSystemType then "fail" else "ok")
        (if hasDeprecatedSystemType then "facts.user.systemType has been removed; derive os from myconfig.hostContext.system" else "facts.user.systemType not set"))
      (mk "facts.architecture"
        (if hasDeprecatedArchitecture then "fail" else "ok")
        (if hasDeprecatedArchitecture then "facts.user.architecture has been removed; derive arch from myconfig.hostContext.system" else "facts.user.architecture not set"))
      (mk "facts.stateVersion"
        (if optionalAttrs stateVersion then "ok" else "fail")
        (if stateVersion == null then "facts.user.stateVersion not set (defaults apply)"
        else if builtins.isAttrs stateVersion then "facts.user.stateVersion set"
        else "facts.user.stateVersion must be an attrset"))
      (mk "facts.stateVersion.home"
        (if stateHome == null || builtins.isString stateHome then "ok" else "fail")
        (if stateHome == null then "facts.user.stateVersion.home not set (default applies)"
        else if builtins.isString stateHome then stateHome
        else "facts.user.stateVersion.home must be a string"))
      (mk "facts.stateVersion.darwin"
        (if stateDarwin == null || builtins.isInt stateDarwin then "ok" else "fail")
        (if stateDarwin == null then "facts.user.stateVersion.darwin not set (default applies)"
        else if builtins.isInt stateDarwin then builtins.toString stateDarwin
        else "facts.user.stateVersion.darwin must be an integer"))
      (mk "facts.machines"
        (if optionalAttrs machines then "ok" else "fail")
        (if machines == null then "facts.machines not set (optional)"
        else if builtins.isAttrs machines then "facts.machines set"
        else "facts.machines must be an attrset"))
      (mk "facts.binaryCaches"
        (if optionalAttrs binaryCaches then "ok" else "fail")
        (if binaryCaches == null then "facts.binaryCaches not set (optional)"
        else if builtins.isAttrs binaryCaches then "facts.binaryCaches set"
        else "facts.binaryCaches must be an attrset"))
      (mk "facts.binaryCaches.substituters"
        (if optionalListOfStrings substituters then "ok" else "fail")
        (if substituters == null then "facts.binaryCaches.substituters not set (optional)"
        else if builtins.isList substituters then "facts.binaryCaches.substituters set"
        else "facts.binaryCaches.substituters must be a list of strings"))
      (mk "facts.binaryCaches.trustedPublicKeys"
        (if optionalListOfStrings trustedPublicKeys then "ok" else "fail")
        (if trustedPublicKeys == null then "facts.binaryCaches.trustedPublicKeys not set (optional)"
        else if builtins.isList trustedPublicKeys then "facts.binaryCaches.trustedPublicKeys set"
        else "facts.binaryCaches.trustedPublicKeys must be a list of strings"))
    ];

  rawFactsChecksText = rawFacts:
    builtins.concatStringsSep "\n" (
      map
        (check: "${check.name}|${check.status}|${check.message}")
        (rawFactsChecks rawFacts)
    );

  renderBootstrapFacts = { username, exampleHost ? "own_mac" }:
    ''
      {
        user = {
          username = ${builtins.toJSON username};

          # Optional for Git identity:
          # fullName = "Your Name";
          # email = "you@example.com";

          # Optional overrides:
          # homeDirectory = "/Users/${username}";
          # stateVersion = {
          #   home = "${defaultStateVersion.home}";
          #   darwin = ${builtins.toString defaultStateVersion.darwin};
          # };
        };

        # Optional machine metadata for tools.system.hostnames:
        # machines = {
        #   ${exampleHost} = {
        #     computerName = "Your Mac";
        #     localHostName = "your-mac";
        #     hostName = "your-mac";
        #     domain = "local";
        #     keyboardType = "ansi";
        #   };
        # };
      }
    '';
in
{
  inherit
    buildHostModel
    defaultStateVersion
    normalizeRawFacts
    parseSystem
    rawFactsChecks
    rawFactsChecksText
    renderBootstrapFacts
    ;
}

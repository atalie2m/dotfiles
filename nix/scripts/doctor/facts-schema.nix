{ factsFile }:
let
  x = import factsFile;

  optionalString = value: value == null || builtins.isString value;
  optionalInt = value: value == null || builtins.isInt value;
  optionalAttrs = value: value == null || builtins.isAttrs value;
  optionalListOfStrings = value: value == null || (builtins.isList value && builtins.all builtins.isString value);

  hasRoot = builtins.isAttrs x;
  user = if hasRoot && builtins.hasAttr "user" x then x.user else null;
  hasUser = builtins.isAttrs user;

  username = if hasUser && builtins.hasAttr "username" user then user.username else null;
  usernameIsString = builtins.isString username;
  usernameNonEmpty = usernameIsString && username != "";

  fullName = if hasUser && builtins.hasAttr "fullName" user then user.fullName else null;
  email = if hasUser && builtins.hasAttr "email" user then user.email else null;
  homeDirectory = if hasUser && builtins.hasAttr "homeDirectory" user then user.homeDirectory else null;
  homeDirLooksAbsolute = builtins.isString homeDirectory && builtins.match "^/.+" homeDirectory != null;
  platform = if hasUser && builtins.hasAttr "platform" user then user.platform else null;

  stateVersion = if hasUser && builtins.hasAttr "stateVersion" user then user.stateVersion else null;
  stateHome = if builtins.isAttrs stateVersion && builtins.hasAttr "home" stateVersion then stateVersion.home else null;
  stateDarwin = if builtins.isAttrs stateVersion && builtins.hasAttr "darwin" stateVersion then stateVersion.darwin else null;

  machines = if hasRoot && builtins.hasAttr "machines" x then x.machines else null;
  binaryCaches = if hasRoot && builtins.hasAttr "binaryCaches" x then x.binaryCaches else null;
  substituters =
    if builtins.isAttrs binaryCaches && builtins.hasAttr "substituters" binaryCaches
    then binaryCaches.substituters
    else null;
  trustedPublicKeys =
    if builtins.isAttrs binaryCaches && builtins.hasAttr "trustedPublicKeys" binaryCaches
    then binaryCaches.trustedPublicKeys
    else null;

  mk = name: status: message: "${name}|${status}|${message}";
in
builtins.concatStringsSep "\n" [
  (mk "facts.schema.root" (if hasRoot then "ok" else "fail")
    (if hasRoot then "facts is an attrset" else "facts.nix must return an attrset"))
  (mk "facts.schema.user" (if hasUser then "ok" else "fail")
    (if hasUser then "facts.user is an attrset" else "facts.user must be an attrset"))
  (mk "facts.username" (if usernameNonEmpty then "ok" else "fail")
    (if usernameNonEmpty then username else "facts.user.username must be a non-empty string"))
  (mk "facts.fullName" (if optionalString fullName then "ok" else "fail")
    (if fullName == null then "facts.user.fullName not set (optional)"
    else if builtins.isString fullName then "facts.user.fullName set"
    else "facts.user.fullName must be a string"))
  (mk "facts.email" (if optionalString email then "ok" else "fail")
    (if email == null then "facts.user.email not set (optional)"
    else if builtins.isString email then "facts.user.email set"
    else "facts.user.email must be a string"))
  (mk "facts.homeDirectory" (if optionalString homeDirectory then "ok" else "fail")
    (if homeDirectory == null then "facts.user.homeDirectory not set (auto-derived)"
    else if builtins.isString homeDirectory then homeDirectory
    else "facts.user.homeDirectory must be a string"))
  (mk "facts.homeDirectoryFormat"
    (if homeDirectory == null then "ok"
    else if !builtins.isString homeDirectory then "fail"
    else if homeDirLooksAbsolute then "ok" else "warn")
    (if homeDirectory == null then "facts.user.homeDirectory not set (auto-derived)"
    else if !builtins.isString homeDirectory then "facts.user.homeDirectory must be a string"
    else if homeDirLooksAbsolute then "facts.user.homeDirectory is absolute"
    else "facts.user.homeDirectory should be an absolute path"))
  (mk "facts.platform" (if optionalString platform then "ok" else "fail")
    (if platform == null then "facts.user.platform not set (defaults to aarch64-darwin)"
    else if builtins.isString platform then platform
    else "facts.user.platform must be a string"))
  (mk "facts.stateVersion" (if optionalAttrs stateVersion then "ok" else "fail")
    (if stateVersion == null then "facts.user.stateVersion not set (optional)"
    else if builtins.isAttrs stateVersion then "facts.user.stateVersion set"
    else "facts.user.stateVersion must be an attrset"))
  (mk "facts.stateVersion.home" (if optionalString stateHome then "ok" else "fail")
    (if stateHome == null then "facts.user.stateVersion.home not set (optional)"
    else if builtins.isString stateHome then stateHome
    else "facts.user.stateVersion.home must be a string"))
  (mk "facts.stateVersion.darwin" (if optionalInt stateDarwin then "ok" else "fail")
    (if stateDarwin == null then "facts.user.stateVersion.darwin not set (optional)"
    else if builtins.isInt stateDarwin then builtins.toString stateDarwin
    else "facts.user.stateVersion.darwin must be an integer"))
  (mk "facts.machines" (if optionalAttrs machines then "ok" else "fail")
    (if machines == null then "facts.machines not set (optional)"
    else if builtins.isAttrs machines then "facts.machines set"
    else "facts.machines must be an attrset"))
  (mk "facts.binaryCaches" (if optionalAttrs binaryCaches then "ok" else "fail")
    (if binaryCaches == null then "facts.binaryCaches not set (optional)"
    else if builtins.isAttrs binaryCaches then "facts.binaryCaches set"
    else "facts.binaryCaches must be an attrset"))
  (mk "facts.binaryCaches.substituters" (if optionalListOfStrings substituters then "ok" else "fail")
    (if substituters == null then "facts.binaryCaches.substituters not set (optional)"
    else if builtins.isList substituters then "facts.binaryCaches.substituters set"
    else "facts.binaryCaches.substituters must be a list of strings"))
  (mk "facts.binaryCaches.trustedPublicKeys" (if optionalListOfStrings trustedPublicKeys then "ok" else "fail")
    (if trustedPublicKeys == null then "facts.binaryCaches.trustedPublicKeys not set (optional)"
    else if builtins.isList trustedPublicKeys then "facts.binaryCaches.trustedPublicKeys set"
    else "facts.binaryCaches.trustedPublicKeys must be a list of strings"))
]

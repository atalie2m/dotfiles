{ buildGoModule
, fetchFromGitHub
, lib
}:

buildGoModule rec {
  pname = "roots";
  version = "0.4.1";

  src = fetchFromGitHub {
    owner = "k1LoW";
    repo = "roots";
    rev = "v${version}";
    hash = "sha256-ACMRfWY/lhc3C/KVhuUyS1rgkSHGWPxZrmYt+pXupJI=";
  };

  vendorHash = "sha256-uxcT5VzlTCxxnx09p13mot0wVbbas/otoHdg7QSDt4E=";

  meta = {
    description = "Explore multiple root directories in a repository or monorepo";
    homepage = "https://github.com/k1LoW/roots";
    license = lib.licenses.mit;
    mainProgram = "roots";
    platforms = lib.platforms.unix;
  };
}

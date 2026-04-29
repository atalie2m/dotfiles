final: prev: {
  kvazaar = prev.kvazaar.overrideAttrs (old: {
    doCheck = if prev.stdenv.hostPlatform.isDarwin then false else old.doCheck or true;
  });

  chromaprint = prev.chromaprint.overrideAttrs (old: {
    doCheck = if prev.stdenv.hostPlatform.isDarwin then false else old.doCheck or true;
  });

  ffmpeg-full = prev.ffmpeg-full.overrideAttrs (old: {
    doCheck = if prev.stdenv.hostPlatform.isDarwin then false else old.doCheck or true;
  });

  direnv = prev.direnv.overrideAttrs (old: {
    doCheck = if prev.stdenv.hostPlatform.isDarwin then false else old.doCheck or true;
  });

  roots = prev.roots or (final.callPackage ./roots { });
}

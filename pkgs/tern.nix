{
  lib,
  inputs,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      version = "0.9.21";
      buildId = "20261114-090304-bde0861";
      pname = "tern";
      baseUrl = "https://build.stencil.so/d/tern/${buildId}";

      assets = {
        x86_64-linux = {
          asset = "Tern-${version}-linux-x86_64.tar.gz";
          sha256 = "655cf7fac7ad1aac3153e4d0d9fe4772c147b5bf925d5a0fd10bb9beeb133adf";
        };
        aarch64-linux = {
          asset = "Tern-${version}-linux-arm64.tar.gz";
          sha256 = "715629458e58f0b9576358a8995f99220a197f84b9b8145fbb4bbea65585c428";
        };
        aarch64-darwin = {
          asset = "Tern-${version}-macos-arm64.dmg";
          sha256 = "9ecc90f95857af7c3f58bf2724ade7e9737c14791bc6fecee39542539df4f594";
        };
      };

      meta = {
        description = "Tern — the agent IDE: terminals, panes and agents in one workspace";
        homepage = "https://tern.build";
        license = lib.licenses.unfree;
        mainProgram = pname;
        platforms = builtins.attrNames assets;
      };

      src = pkgs.fetchurl {
        url = "${baseUrl}/${assets.${system}.asset}";
        sha256 = assets.${system}.sha256;
        name = assets.${system}.asset;
      };

      linuxPackage = pkgs.stdenv.mkDerivation {
        inherit
          pname
          version
          meta
          src
          ;
        nativeBuildInputs = [
          pkgs.autoPatchelfHook
          pkgs.makeWrapper
        ];
        buildInputs = [
          pkgs.stdenv.cc.cc.lib
          pkgs.libxcb
          pkgs.libxkbcommon
          pkgs.mesa
          pkgs.vulkan-loader
          pkgs.glib
        ];
        installPhase = ''
          runHook preInstall
          install -Dm755 tern $out/bin/tern
          runHook postInstall
        '';
        postFixup = ''
          wrapProgram $out/bin/tern \
            --prefix LD_LIBRARY_PATH : ${pkgs.libxcb}/lib:${pkgs.libxkbcommon}/lib:${pkgs.mesa}/lib:${pkgs.vulkan-loader}/lib \
            --prefix PATH : ${pkgs.glib}/bin
        '';
      };

      darwinPackage = pkgs.stdenvNoCC.mkDerivation {
        inherit
          pname
          version
          meta
          src
          ;
        nativeBuildInputs = [
          pkgs.makeWrapper
          pkgs.undmg
        ];
        sourceRoot = ".";
        installPhase = ''
          runHook preInstall
          mkdir -p $out/Applications $out/bin
          cp -R *.app $out/Applications/
          makeWrapper $out/Applications/Tern.app/Contents/MacOS/tern $out/bin/${pname}
          runHook postInstall
        '';
        dontFixup = true;
      };
    in
    lib.mkIf (builtins.hasAttr system assets) {
      packages.${pname} = if pkgs.stdenv.hostPlatform.isDarwin then darwinPackage else linuxPackage;
    };
}

# onekey-wallet — OneKey Wallet desktop app (https://onekey.so), built from source.
# Flake-parts module: packages.<system>.onekey-wallet (Linux only).
#
# Upstream (OneKeyHQ/app-monorepo) ships AppImages and dmgs; this builds the
# desktop renderer (rspack) and main process (esbuild) from the v6.6.4 tag and
# runs them on nixpkgs' electron, laid out like an electron-builder package:
#   $out/lib/onekey-wallet/            electron runtime, binary renamed
#   $out/lib/onekey-wallet/resources/app   asar-equivalent app directory
#   $out/lib/onekey-wallet/resources/{bin,static}  extraResources
#
# Still binary from upstream: the hardware-wallet bridge daemons committed under
# apps/desktop/public/static/bin/bridge (upstream publishes no source for them).
#
# The rename of the electron binary matters: Electron reports app.isPackaged =
# false when the executable is named `electron`, which makes the app load
# http://localhost:3001 instead of the built bundle.
{
  lib,
  inputs,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs { inherit system; };

      pname = "onekey-wallet";
      version = "6.6.4";
      rev = "208f4a687ddaa94056624f7b7541417ed530c1af";

      src = pkgs.fetchzip {
        url = "https://github.com/OneKeyHQ/app-monorepo/archive/${rev}.tar.gz";
        hash = "sha256-pNVFPYHF3qOxnUrHkQ6hgpVDni6FNj4AZ8pF9qlajsU=";
      };

      yarn-berry = pkgs.yarn-berry_4;

      # Yarn Berry offline cache for yarn.lock; the hash is reported by the
      # first build that runs with lib.fakeHash.
      # missing-hashes.json covers the lockfile entries npm published without a
      # checksum (`yarn-berry-fetcher missing-hashes yarn.lock`).
      offlineCache = yarn-berry.passthru.fetchYarnBerryDeps {
        inherit src;
        missingHashes = ./onekey-wallet-missing-hashes.json;
        hash = "sha256-xPphY6G/n+8Qdnqr8VkWFDr0ij/dpzXAyUMkG4VpnKw=";
      };

      bridgeArch = if pkgs.stdenv.hostPlatform.isAarch64 then "linux-arm64" else "linux-x64";

      onekey-wallet = pkgs.stdenv.mkDerivation {
        inherit
          pname
          version
          src
          offlineCache
          ;

        # yarnBerryConfigHook diffs this against the cache's copy.
        missingHashes = ./onekey-wallet-missing-hashes.json;

        nativeBuildInputs = with pkgs; [
          nodejs_22
          yarn-berry
          yarn-berry.passthru.yarnBerryConfigHook
          git
          python3
          pkg-config
          autoPatchelfHook
          makeWrapper
        ];

        buildInputs = with pkgs; [
          stdenv.cc.cc.lib
          systemd
          libusb1
        ];

        # apps/desktop/scripts/build.js stamps `git rev-parse HEAD`, and the
        # release tarball has no .git. Everything else falls through to git.
        postPatch = ''
          mkdir -p .git-shim
          printf '#!/bin/sh\nif [ "$1" = rev-parse ]; then echo ${rev}; exit 0; fi\nexec ${pkgs.git}/bin/git "$@"\n' > .git-shim/git
          chmod +x .git-shim/git
        '';

        preConfigure = ''
          export PATH=$PWD/.git-shim:$PATH
        '';

        buildPhase = ''
          runHook preBuild
          export YARN_IGNORE_PATH=1
          export NODE_OPTIONS=--max-old-space-size=8192
          yarn workspace @onekeyhq/desktop build:renderer
          yarn workspace @onekeyhq/desktop build:main
          runHook postBuild
        '';

        dontAutoPatchelf = true;

        installPhase = ''
          runHook preInstall

          appBuild=apps/desktop/app
          electronDir=$out/lib/onekey-wallet
          resDir=$electronDir/resources
          appDir=$resDir/app

          mkdir -p $out/bin $electronDir
          cp -r ${pkgs.electron_44.passthru.unwrapped}/libexec/electron/. $electronDir/
          chmod -R u+w $electronDir
          rm -f $electronDir/resources/default_app.asar
          mv $electronDir/electron $electronDir/onekey-wallet

          mkdir -p $appDir $resDir/static/images/icons $resDir/bin $out/share/applications $out/share/icons/hicolor/512x512/apps
          cp -r $appBuild/dist $appDir/dist
          cp -r $appBuild/build $appDir/build
          cp -a node_modules $appDir/node_modules

          substituteInPlace $appBuild/package.json \
            --replace-fail '"version": "1.0.0"' '"version": "${version}"'
          cp $appBuild/package.json $appDir/package.json

          # electron-builder extraResources (see electron-builder.config.js).
          install -Dm644 $appBuild/build/static/preload.js $resDir/static/preload.js
          install -Dm644 $appBuild/build/static/images/icons/512x512.png \
            $resDir/static/images/icons/512x512.png
          cp -r $appBuild/build/static/bin/bridge/${bridgeArch} $resDir/bin/bridge

          install -Dm644 $appBuild/build/static/udev/99-onekey.rules \
            $out/lib/udev/rules.d/99-onekey.rules

          install -Dm644 $appBuild/build/static/images/icons/512x512.png \
            $out/share/icons/hicolor/512x512/apps/${pname}.png

          cat > $out/share/applications/${pname}.desktop <<EOF
          [Desktop Entry]
          Name=OneKey
          Comment=Multi-chain crypto wallet
          Exec=$out/bin/${pname} %U
          Icon=${pname}
          Terminal=false
          Type=Application
          Categories=Utility;
          MimeType=x-scheme-handler/onekey-wallet;
          EOF

          # Reuse nixpkgs' electron wrapper (GTK/GIO/gsettings environment) and
          # point it at our app directory instead of electron's default app.
          cp ${pkgs.electron_44}/bin/electron $out/bin/${pname}
          chmod u+w $out/bin/${pname}
          substituteInPlace $out/bin/${pname} \
            --replace-fail "${pkgs.electron_44.passthru.unwrapped}/libexec/electron/electron" \
              "$electronDir/onekey-wallet"

          wrapProgram $out/bin/${pname} \
            --add-flags "--no-sandbox" \
            --add-flags "$appDir" \
            --prefix LD_LIBRARY_PATH : ${
              lib.makeLibraryPath [
                pkgs.stdenv.cc.cc.lib
                pkgs.systemd
                pkgs.libusb1
              ]
            }

          autoPatchelf $resDir/bin

          runHook postInstall
        '';

        meta = {
          description = "OneKey Wallet — multi-chain crypto wallet";
          homepage = "https://onekey.so/";
          changelog = "https://github.com/OneKeyHQ/app-monorepo/releases";
          license = lib.licenses.mit;
          mainProgram = pname;
          platforms = [
            "x86_64-linux"
            "aarch64-linux"
          ];
          maintainers = [ ];
        };
      };
    in
    lib.mkIf (pkgs.stdenv.hostPlatform.isLinux) {
      packages.${pname} = onekey-wallet;
    };
}

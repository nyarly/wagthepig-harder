{
  description = "wagthepig is a web app to help with the What Are We Going to Play Game";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    # Until https://github.com/NixOS/nixpkgs/pull/414495
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    mkElmDerivation.url = "github:jeslie0/mkElmDerivation";
    crate2nix = {
      url = "github:nix-community/crate2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = {
    allow-import-from-derivation = true; # my default, but useful for others
  };

  outputs =
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      flake-utils,
      mkElmDerivation,
      crate2nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = (
          import nixpkgs {
            overlays = [ mkElmDerivation.overlays.mkElmDerivation ];
            inherit system;
          }
        );

        runDeps = with pkgs; [
          openssl
        ];

        buildDeps =
          with pkgs;
          [
            pkg-config
          ]
          ++ runDeps;
      in
      {
        packages =
          let
            version = "0.1.0";

            cargoNix = crate2nix.tools.${system}.appliedCargoNix {
              name = "wag-the-pig";
              src = ./backend;
            };

          in
          rec {
            wag-the-pig-frontend = pkgs.mkElmDerivation {
              name = "wag-the-pig-frontend";
              inherit version;

              src = ./frontend/src;

              nativeBuildInputs = with pkgs; [
                elmPackages.elm
                lightningcss
              ];

              buildPhase = ''
                mkdir dist # in src, not sibling
                mkdir dist/{css,js}
                cp -av static/assets dist/
                cp -av static/html dist/
                cp -av static/js/ports/ dist/js/
                elm make elm/Main.elm --output=dist/js/main.js --optimize
                lightningcss --bundle --output-file dist/css/index.css css/main.css
              '';

              installPhase = ''
                mkdir $out
                cp -a dist/* $out
              '';
            };

            wag-the-pig = cargoNix.rootCrate.build.overrideAttrs (previousAttrs: {
              preBuild = ''
                rm -rf frontend
                cp -a ${wag-the-pig-frontend} frontend
              '';

              checkFlags = "--skip db::";

              buildPhase = ''
                export CARGO=${pkgs.cargo}/bin/cargo

              ''
              + previousAttrs.buildPhase;

              meta = with pkgs.lib; {
                description = "A web app for pre-deciding games to play";
                longDescription = ''
                  wagthepig is a web app to help with the What Are We Going to Play Game
                '';
                homepage = "https://crates.io/crates/wagthepig";
                license = licenses.mpl20;
                maintainers = [ maintainers.nyarly ];
              };
            });

            wag-the-pig-migrations = pkgs.stdenv.mkDerivation {
              pname = "wag-the-pig-migrations";
              inherit version;
              src = ./backend/migrations;

              installPhase = ''
                mkdir $out
                cp -a * $out
              '';
            };

            # TODO a migrations package

            wag-the-pig-brp = pkgs.rustPlatform.buildRustPackage rec {
              crateName = "wag-the-pig";

              src = ./backend;

              name = "${crateName}-${version}";

              outputs = [
                "out"
                "migrations"
              ];

              postInstall = ''
                mkdir -p $migrations
                cp migrations/* $migrations
              '';

              cargoLock.lockFile = backend/Cargo.lock;

              nativeBuildInputs = buildDeps;

              buildInputs = buildDeps;

              preBuild = ''
                rm -rf frontend
                cp -a ${wag-the-pig-frontend} frontend
              '';

              checkFlags = "--skip db::";

              meta = with pkgs.lib; {
                description = "A web app for pre-deciding games to play";
                longDescription = ''
                  wagthepig is a web app to help with the What Are We Going to Play Game
                '';
                homepage = "https://crates.io/crates/wagthepig";
                license = licenses.mpl20;
                maintainers = [ maintainers.nyarly ];
              };
            };
          };
        nixosModules.wag-the-pig =
          {
            config,
            lig,
            pkgs,
            ...
          }@params:
          {
            options = import nix/backend/options.nix self.packages.${system} params;
            config = import nix/backend/config.nix params;
          };
        devShells.default =
          let
            unstable-pkgs = (
              import nixpkgs-unstable {
                overlays = [ mkElmDerivation.overlays.mkElmDerivation ];
                inherit system;
              }
            );

            elm-pkgs = unstable-pkgs.elmPackages;
          in
          # if you don't what to use Nix, here are the dependencies you need:
          pkgs.mkShell {
            buildInputs =
              with pkgs;
              [
                cargo
                cargo-expand
                rustc
                rust-analyzer
                clippy

                pkgs.crate2nix

                nodejs_latest
                elm-pkgs.elm
                elm-pkgs.elm-test-rs
                elm-pkgs.elm-live
                elm-pkgs.elm-review
                elm-pkgs.elm-format
                elm-pkgs.elm-doc-preview
                lightningcss
                elm2nix

                process-compose
                watchexec
                postgresql_15
                sqlx-cli
                biscuit-cli
                mailpit
                openssl
                nginx
                envsubst
              ]
              ++ buildDeps; # If you're doing your own installs, you can ignore this
          };
      }
    );
}

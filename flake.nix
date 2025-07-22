{
  description = "wagthepig is a web app to help with the What Are We Going to Play Game";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
    mkElmDerivation.url = "github:jeslie0/mkElmDerivation";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      mkElmDerivation,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = (
          import "${nixpkgs}" {
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

            wag-the-pig = pkgs.rustPlatform.buildRustPackage rec {
              crateName = "wag-the-pig";

              src = ./backend;

              name = "${crateName}-${version}";

              outputs = [
                "out"
                "migrations"
              ];

              cargoHash = "sha256-AkdsFb7M6zonKumyrJCD40xH0wFyCZY/FJd4w14Afyg=";

              nativeBuildInputs = buildDeps;

              buildInputs = buildDeps;

              preBuild = ''
                rm -rf frontend
                cp -a ${wag-the-pig-frontend} frontend
              '';

              postInstall = ''
                mkdir -p $migrations
                cp migrations/* $migrations
              '';

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
        devShells.default = pkgs.mkShell {
          buildInputs =
            with pkgs;
            [
              cargo
              cargo-expand
              rustc
              rust-analyzer
              clippy

              nodejs_latest
              elmPackages.elm
              elmPackages.elm-test-rs
              elmPackages.elm-live
              elmPackages.elm-review
              elmPackages.elm-doc-preview
              lightningcss
              elm2nix

              process-compose
              watchexec
              postgresql_15
              sqlx-cli
              biscuit-cli
              mailpit
              openssl
            ]
            ++ buildDeps;
        };
      }
    );
}

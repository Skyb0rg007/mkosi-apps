{
  description = "mkosi-apps flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    skyenet.url = "github:Skyb0rg007/packages?dir=NixOS";
    skyenet.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      skyenet,
    }:
    let
      inherit (nixpkgs) lib;
      systems = [ "x86_64-linux" ];
      forEachSystem = lib.genAttrs systems;
    in
    {
      packages = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          skyenetPkgs = skyenet.legacyPackages.${system};
        in
        {
          mkosiFhs = pkgs.buildFHSEnv {
            name = "mkosi";
            targetPkgs = pkgs: [
              pkgs.mkosi
              pkgs.apt
              pkgs.cacert
              pkgs.curl
              pkgs.dpkg
              pkgs.gnupg
              pkgs.zstd
              pkgs.erofs-utils
              pkgs.e2fsprogs
              pkgs.sequoia-sqop
              pkgs.go
              skyenetPkgs.debian-archive-keyring
            ];
            profile = ''
              export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
              export CURL_CA_BUNDLE=$SSL_CERT_FILE
            '';
            runScript = "mkosi";
          };
        }
      );

      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              self.packages.${system}.mkosiFhs
              pkgs.nixfmt
              pkgs.treefmt
              pkgs.debian-devscripts
              pkgs.dpkg
              pkgs.sequoia-sqop
            ];
          };
        }
      );

    };
}

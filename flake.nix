{
  description = "mkosi-apps flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
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
              pkgs.debian-archive-keyring
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
              pkgs.python3 # scripts/foreign-shift.py
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

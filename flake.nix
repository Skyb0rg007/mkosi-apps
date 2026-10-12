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
      devShells = forEachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          # mkosi runs directly, not in a buildFHSEnv: bubblewrap's user
          # namespace makes systemd-nsresourced refuse mkosi's range request
          # (DynamicRangeUnavailable). The host tools below only bootstrap the
          # default tools tree; everything else runs inside it. That bootstrap
          # also needs /usr/share/keyrings/debian-archive-keyring.gpg on the
          # host, see the README.
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.mkosi
              pkgs.apt
              pkgs.gnupg
              pkgs.sequoia-sqv
              pkgs.zstd
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

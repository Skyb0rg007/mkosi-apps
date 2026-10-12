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
            # Nix exports SOURCE_DATE_EPOCH=315532800, which makes mkosi clamp
            # every mtime in the images to 1980, /usr's included. Then no new
            # version's /usr is newer than a machine's /etc/.updated, and
            # ConditionNeedsUpdate= never reruns ldconfig.service and friends
            # after an upgrade. As in ParticleOS, builds keep their own time.
            shellHook = ''
              unset SOURCE_DATE_EPOCH
            '';
          };
        }
      );

    };
}

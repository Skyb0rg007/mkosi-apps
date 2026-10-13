# Apps as VMs, with A/B updates

The `vm` profile builds an app as a bootable disk image instead of a
container, which updates itself with
[systemd-sysupdate](https://www.freedesktop.org/software/systemd/man/latest/systemd-sysupdate.html):
it downloads a new version of the image's `/usr` into a second slot, boots
into it, and falls back to the previous version if that does not come up. It
follows [ParticleOS](https://github.com/systemd/particleos), less Secure Boot
and the verity signature.

    mkosi --profile=soju,vm build    # mkosi.output/vm/soju_0.10.1-1.raw
    mkosi --profile=soju,vm vm       # try it in QEMU, on a throwaway copy

## The disk

As built, the image holds:

| Partition | Contents |
|---|---|
| ESP, 512M | systemd-boot, and the UKI, `soju_0.10.1-1.efi` |
| `usr-verity`, 128M | the dm-verity hashes of `/usr`, labelled `soju_0.10.1-1_verity` |
| `usr` | `/usr`, as erofs, minimized, labelled `soju_0.10.1-1` |

On the first boot, `systemd-repart` completes it in the initrd, from
`/usr/lib/repart.d` (`mkosi.profiles/vm/mkosi.extra`):

| Partition | Contents |
|---|---|
| `usr`, grown to 4G | the A slot |
| `usr-verity` and `usr`, 128M and 4G, labelled `_empty` | the B slot |
| `root`, the rest of the disk, ext4 | `/etc` and `/var`, which the machine populates from `/usr` as a container does `root/` (see [design.md](design.md#usr-is-enough-to-boot)) |

So a disk needs to be bigger than the image: about 9G plus the app's data. The
UKI's command line carries `usrhash=`, the verity root hash of its own `/usr`,
which also names that partition, so each UKI boots the `/usr` it was built
with, and `/usr` is verified as it is read.

To run an image elsewhere, copy it to a disk of the size it should have, e.g.
`cp --sparse=always soju_0.10.1-1.raw disk.raw && truncate -s 32G disk.raw`,
and boot it with UEFI firmware: `systemd-vmspawn --image=disk.raw`, libvirt,
or a cloud provider's custom image import.

## Updates

`systemd-sysupdate` finds new versions in a directory served over HTTP(S), one
per app, through the transfers in `/usr/lib/sysupdate.d` (templates in
`mkosi.profiles/vm/sysupdate.d/`). `systemd-sysupdate-update.timer` looks for
one 15 minutes after boot and every two hours, and installs it:

1. the new `usr-verity` and `usr` partitions into the slot that does not hold
   the booted version, labelled with the new version;
2. its UKI into the ESP, as `soju_0.10.1-2+3-0.efi`: three tries left.

systemd-boot boots the newest UKI, which, after
`systemd-sysupdate-reboot.timer` reboots the machine (daily at 04:10, within
half an hour), selects the new `/usr`. When the boot reaches
`boot-complete.target`, `systemd-bless-boot` drops the counter and the
version is good. A version that fails three boots is skipped in favour of the
previous one, which is still in its slot; the next update overwrites the
failed one. The data on `root` is shared by both: an app that migrates its
data on start, as most do, cannot go back past that migration this way.

A version that fails in the initrd waits in the emergency shell rather than
rebooting, so it takes resetting the VM, three times, to fall back.

### Setting it up

The updates' `SHA256SUMS` must be signed. systemd-pull verifies its signature
against the certificate the image carries. Make a key, from the dev shell:

    sqop generate-key "mkosi-apps updates" > updates.key
    sqop extract-cert --no-armor < updates.key > mkosi.profiles/vm/import-pubring.pgp

Keep `updates.key` safe, outside the repository; `import-pubring.pgp` is in
`.gitignore`.

Then tell the images where the updates are, in `mkosi.local.conf`, which mkosi
reads and git ignores:

    [Build]
    Environment=SYSUPDATE_URL=https://updates.example.com/mkosi-apps

Each app looks in `$SYSUPDATE_URL/<app>/`. Builds of the `vm` profile then
carry the transfers, the certificate in `/etc/systemd/import-pubring.pgp`, and
enable both timers. Without `SYSUPDATE_URL`, they have the A/B layout but
nothing to update from.

### Publishing a version

Build the new version, then add it to the update directory, which any static
web server serves at `SYSUPDATE_URL`:

    mkosi --profile=soju,vm build
    bin/publish-update mkosi.output/vm/soju_0.10.1-2 updates.key /srv/updates

`publish-update` adds the version's `/usr` and verity partitions, compressed,
and its UKI to `/srv/updates/soju/`, then rewrites `SHA256SUMS` for every
version there and signs it as `SHA256SUMS.gpg`. Publishing a version again
replaces it. Remove old versions by hand, and publish again to update the
checksums.

A version must fit a slot: 4G for `/usr` (erofs, compressed), and 128M for its
verity hashes. The biggest app's, paperless's, is 1.8G; wakapi's 0.2G. Machines keep the slot sizes they were installed with, so to
change them, change both `mkosi.repart/` and `mkosi.extra/usr/lib/repart.d/`,
for new machines only.

### By hand

In the VM:

    /usr/lib/systemd/systemd-sysupdate list        # versions, installed and available
    /usr/lib/systemd/systemd-sysupdate update      # install the newest
    /usr/lib/systemd/systemd-sysupdate reboot      # reboot, if a newer one is installed
    bootctl list                                   # the UKIs, with their tries

`updatectl` does the same through `systemd-sysupdated`.

## Not covered

- Secure Boot: the UKIs are unsigned, so anyone who can write the ESP can boot
  something else. mkosi can sign them (`SecureBoot=`), and the verity root hash
  (`Verity=signed`, a `usr-verity-sig` partition, as ParticleOS does), with
  keys enrolled in the VM's firmware.
- Encrypting `root` with a TPM2 (`Encrypt=tpm2` in `30-root.conf`).
- Moving a container's `root/` into a VM's `root` partition, or back.

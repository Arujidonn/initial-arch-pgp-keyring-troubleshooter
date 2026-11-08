# arch-pgp-fix.sh

A troubleshooter script for Arch Linux / LainOS PGP keyring errors during `pacman -Syu`.

## Errors This Fixes

```
error: key "XXXXXXXXXXXXXXXX" could not be looked up remotely
error: failed to synchronize all databases (unable to lock database)
gpg: can't open '/usr/share/pacman/keyrings/archlinux.gpg': Permission denied
error: required key missing from keyring
error: failed to commit transaction (unexpected error)
```

## Usage

```bash
curl -O https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/arch-pgp-fix.sh
chmod +x arch-pgp-fix.sh
bash arch-pgp-fix.sh
```

Or directly:
```bash
bash <(curl -s https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/arch-pgp-fix.sh)
```

## What It Does

| Step | Fix |
|------|-----|
| 1 | Removes stale pacman database lock (`db.lck`) |
| 2 | Fixes keyring file permissions |
| 3 | Reinitializes and repopulates pacman keyring |
| 4 | Patches `SigLevel = Never` in `/etc/pacman.conf` for broken repos |
| 5 | Reinstalls fakeroot |
| 6 | Optionally fixes wlogout PGP error |
| 7 | Syncs databases and upgrades system |

## Compatibility

- Works with `doas`, `sudo`, or as `root` — auto-detected
- Tested on **LainOS** (Arch-based)
- Should work on any Arch Linux derivative

## Why This Happens

Arch Linux uses PGP signing to verify packages. When:
- The keyserver is unreachable
- Keyring file permissions are wrong
- The local keyring is uninitialized or corrupted

...pacman cannot verify package signatures and refuses to install/upgrade.

This script works around the keyserver issue by setting `SigLevel = Never` temporarily and rebuilds the keyring properly.

## ⚠️ Note on SigLevel = Never

Setting `SigLevel = Never` disables package signature verification. This is a **workaround** for keyserver issues. Once your keyring is working again, you should revert `/etc/pacman.conf` to use proper signature checking:

```ini
[options]
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
```

## Credits

Inspired by [ekahPruthvi/Error.sh](https://github.com/ekahPruthvi/Error.sh)

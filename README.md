# Proton OS package repository

Apps made for [Proton OS](https://www.protonos.org), as an APT repository: install them with `apt` or
KDE Discover, and get their updates the same way as every other update on the system.

**Address:** <https://protonos-linux.github.io/apt>

| Package | What it is |
|---|---|
| `proton-security` | [Proton Security](https://github.com/ProtonOS-Linux/proton-security-app), the security center |
| `proton-ip-scanner` | [Proton IP Scanner](https://github.com/ProtonOS-Linux/proton-network-scanner), the network and vulnerability scanner |
| `proton-os-archive-keyring` | Adds this repository to apt, with the key its packages are signed with |

## Add it to a computer

Proton OS has it set up already. On another Debian 13 system with KDE Plasma:

```bash
wget https://protonos-linux.github.io/apt/proton-os-archive-keyring.deb
sudo apt install ./proton-os-archive-keyring.deb
sudo apt update
sudo apt install proton-security proton-ip-scanner
```

The signing key's fingerprint is on the [repository's home page](https://protonos-linux.github.io/apt) and in
`fingerprint.txt`; compare it with `gpg --show-keys /usr/share/keyrings/proton-os-archive-keyring.gpg`.

### Updates

- **KDE Discover** and the update icon in the panel show new versions with the other updates, and install them
  with one click.
- With **automatic updates** on (`unattended-upgrades`, the *Automatic security updates* tile in Proton Security),
  they install by themselves, together with Debian's security updates.
- In a terminal: `sudo apt update && sudo apt upgrade`.

The keyring package installs three files:

| File | Purpose |
|---|---|
| `/usr/share/keyrings/proton-os-archive-keyring.gpg` | The public key. apt only accepts this repository's files when they carry its signature |
| `/etc/apt/sources.list.d/proton-os.sources` | The repository entry (used only with that key, `Signed-By`) |
| `/etc/apt/apt.conf.d/52proton-os-unattended-upgrades` | Lets unattended-upgrades install updates from this repository |

To remove the repository: `sudo apt purge proton-os-archive-keyring` (installed apps stay; they just stop
getting updates).

## How it works

There is no server to maintain. [`publish.yml`](.github/workflows/publish.yml) runs on GitHub Actions:

1. It reads [`apps.txt`](apps.txt) and downloads the `.deb` files attached to the last 3 releases of each app
   (so you can go back a version with `apt install proton-security=<version>`).
2. It builds the keyring package from [`keyring/`](keyring).
3. It writes the package index (`apt-ftparchive`) and the AppStream data for KDE Discover
   ([`scripts/make-dep11.sh`](scripts/make-dep11.sh)), signs it with the Proton OS key (`InRelease`,
   `Release.gpg`), checks the result with a real `apt-get update`, and publishes it on GitHub Pages.

It runs **every hour** (and stops early when nothing changed), on every change to this repository, and on demand.
So a new app release reaches computers within about an hour. To publish it right away: *Actions → Publish
repository → Run workflow*.

### Releasing a new app version

Publish the release in the app's repository as usual (its own workflow attaches the `.deb`). Nothing else is
needed here. To add another app, add its repository to `apps.txt`; its releases must have a `.deb` attached.

### Showing up in KDE Discover

Discover only lists a package as an app (with its icon, description and screenshots, and in search) when the
repository publishes AppStream data for it, in `dists/stable/main/dep11/`. The workflow builds that data from
the metainfo file inside each app's `.deb` (`/usr/share/metainfo/<app id>.metainfo.xml`, kept in the app's
`packaging/` folder). An app without one still installs with apt, but Discover hides it. The build fails if a
package has a metainfo file that produces no entry, so an app can't quietly disappear from Discover.

On a computer, `apt update` downloads the data; Discover picks it up the next time it opens. To check by hand:
`sudo apt update && appstreamcli get org.protonos.ProtonSecurity`.

To add a new app to Discover, give it a metainfo file (copy one of the existing apps') and validate it in its
CI with `appstreamcli validate`. Nothing needs changing here.

### The signing key

The private key is stored only as the repository secret `APT_SIGNING_KEY` (and in the maintainers' offline
backup). The public key is published by the workflow (`proton-os.asc`, and inside the keyring package). Create it
once, on a trusted computer:

```bash
gpg --batch --passphrase '' --quick-gen-key "Proton OS Packages <support@protonos.org>" rsa4096 sign 5y
gpg --list-secret-keys support@protonos.org           # note the long fingerprint
gpg --armor --export-secret-keys support@protonos.org > proton-os-signing-key.PRIVATE.asc
```

Paste the contents of `proton-os-signing-key.PRIVATE.asc` into *Settings → Secrets and variables → Actions →
New repository secret*, named `APT_SIGNING_KEY`. Then store that file offline (a USB stick in a drawer, a
password manager) and delete it from the computer. Never commit it.

**Before the key expires** (5 years) extend it with `gpg --quick-set-expire <fingerprint> 5y`, update the secret,
and bump `keyring/VERSION` so computers get the new key with their next update.

### Settings this repository needs

- *Settings → Pages → Build and deployment → Source:* **GitHub Actions**.
- The `APT_SIGNING_KEY` secret (above).
- Scheduled workflows stop after 60 days without changes to this repository; GitHub emails a warning and one click
  (*Actions → Publish repository → Enable workflow*) turns it back on. Running it by hand after a release also
  works.

## License

The scripts and configuration in this repository are released under the GPL-3.0-or-later, like the apps.
Questions: [support@protonos.org](mailto:support@protonos.org).

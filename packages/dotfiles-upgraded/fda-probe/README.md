# Darwin Full Disk Access probe

This isolated experiment does not rebuild or activate dotfiles. It tests whether
Full Disk Access (FDA) granted to a signed native app covers a launchd-started
root process that runs Nix Bash, `launchctl asuser`, `sudo -n --set-home`, and a
user Bash, as nix-darwin's Home Manager activation does.

The user process creates a unique temporary directory and symlink under
`~/Library/Application Support/Firefox`, then removes both. It never changes
`profiles.ini`. A denial can still leave a temporary directory if cleanup is
also denied; its name starts with `.dotfiles-fda-probe.`.

## Build

Use a real signing identity, not ad-hoc signing (`-`). The identity must remain
available for replacement builds; do not commit or export its private key.

```sh
security find-identity -v -p codesigning
bash packages/dotfiles-upgraded/fda-probe/build.sh \
  /tmp/dotfiles-fda-probe-v1 SIGNING_IDENTITY_HASH "$USER" 1
```

Output directories must not already exist. The script selects the current system
activation's Nix Bash. It compiles and signs the bundle and validates both plists;
it does not install anything. Signing may require a Keychain approval.

## Install and establish the baseline

Inspect the generated plist before installing. The test intentionally launches
through the system launchd domain, not the terminal, to avoid inheriting the
terminal's privacy permission. Do not grant the app FDA before the first run.

```sh
sudo /usr/bin/ditto '/tmp/dotfiles-fda-probe-v1/Dotfiles Updater Probe.app' \
  '/Applications/Dotfiles Updater Probe.app'
sudo /usr/sbin/chown -R root:wheel '/Applications/Dotfiles Updater Probe.app'
sudo /bin/chmod -R go-w '/Applications/Dotfiles Updater Probe.app'
sudo /usr/bin/install -o root -g wheel -m 644 \
  /tmp/dotfiles-fda-probe-v1/com.whexy.dotfiles-updater-probe.plist \
  /Library/LaunchDaemons/com.whexy.dotfiles-updater-probe.plist
sudo /bin/launchctl bootstrap system \
  /Library/LaunchDaemons/com.whexy.dotfiles-updater-probe.plist
sudo /bin/launchctl kickstart system/com.whexy.dotfiles-updater-probe
```

Inspect `/var/log/dotfiles-updater-probe.log` and
`launchctl print system/com.whexy.dotfiles-updater-probe`. The job is one-shot,
with neither RunAtLoad nor KeepAlive. Wait for it to exit before running it again.
A zero last exit code and `PASS` mean access succeeded. If the baseline already
passes, this location does not demonstrate an FDA requirement on this machine;
do not claim that the experiment proved attribution.

## Grant and repeat

In System Settings → Privacy & Security → Full Disk Access, use **+** to select
`/Applications/Dotfiles Updater Probe.app`, then enable it. Do not enable Bash,
Nix, or the terminal for this experiment.

Run `sudo launchctl kickstart system/com.whexy.dotfiles-updater-probe` again.
A baseline denial followed by success is evidence that the app's grant covers
this process chain. If it still fails, inspect TCC attribution before changing
other permissions; an app bundle alone is not proof of responsible-process identity.

## Replacement test

Build revision 2 into a new directory with the **same signing identity**. Compare
its `signing-requirement.txt` with revision 1 and confirm the executable hashes
differ. Unload the finished probe job, replace the installed app with revision 2
using `ditto`, restore root ownership and remove group/other write permission,
then bootstrap and kickstart the same plist. Do not toggle FDA again.

```sh
sudo launchctl bootout system/com.whexy.dotfiles-updater-probe
# Replace the app as above, using the revision-2 build directory.
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/com.whexy.dotfiles-updater-probe.plist
sudo launchctl kickstart system/com.whexy.dotfiles-updater-probe
```

Require revision 2's `PASS` before treating permission persistence as verified.
Also repeat with a different Nix Bash after a system update. This probe does not
validate all activation operations, signing-certificate renewal, or daemon
self-replacement during a real switch. Production integration needs those tests.

## Observed result

On the tested macOS 27.0 machine (build 26A428):

- Revision 1 without FDA failed to create the temporary directory with
  `Operation not permitted`, exiting with code 1.
- After granting FDA only to **Dotfiles Updater Probe**, revision 1 created and
  removed the temporary symlink successfully, exiting with code 0.
- Replacing the app with revision 2, signed with the same Apple Development
  identity, succeeded without changing the FDA grant. The executable hashes
  differed and the designated signing requirements matched.

This verifies the tested user-switching process chain and one signed executable
replacement. It does not yet verify a different Nix Bash, full system activation,
certificate renewal, or production daemon lifecycle behavior.

## Remove

After the probe exits, unload it and remove only its own artifacts:

```sh
sudo launchctl bootout system/com.whexy.dotfiles-updater-probe
sudo rm /Library/LaunchDaemons/com.whexy.dotfiles-updater-probe.plist
sudo rm -r '/Applications/Dotfiles Updater Probe.app'
sudo rm /var/log/dotfiles-updater-probe.log
```

Remove the probe's FDA entry in System Settings. No production updater settings
are changed by this experiment.

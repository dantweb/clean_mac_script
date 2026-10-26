# clean_mac_script

An interactive disk-cleanup script for macOS, aimed at developer machines where
Xcode, Docker, Android Studio, JetBrains IDEs and package managers quietly eat
hundreds of gigabytes.

It shows the size of every item and asks before deleting anything.

**It never removes applications** — only caches, build artifacts and developer data.

## Requirements

- macOS 10.15 (Catalina) or newer — the script uses `zsh`
- Your normal user account (the script calls `sudo` itself only for items under
  `/Library` or `/Applications`)

## Usage

```sh
git clone https://github.com/dantweb/clean_mac_script.git
cd clean_mac_script

./cleanup_mac.sh --dry-run     # show what could be freed, delete nothing
./cleanup_mac.sh --yes-safe    # auto-delete SAFE items, ask about the rest
./cleanup_mac.sh               # ask y/N for every item
```

Always start with `--dry-run`.

## What it cleans

Items are labelled by risk:

- **SAFE** — caches and build artifacts that are regenerated automatically.
- **REVIEW** — data you might still need (emulators, simulator data, Docker images).
  These always prompt, default to **No**, and are never auto-accepted.

| Area | SAFE | REVIEW |
|------|------|--------|
| Xcode / iOS | Old iOS DeviceSupport (keeps newest per device), DerivedData, simulator dyld caches, unavailable simulators | Older simulator runtimes, erase all simulator data |
| Android | Gradle caches | Emulator images (`~/.android/avd`), Android SDK |
| Docker | — | `docker system prune -a --volumes` (Docker must be running) |
| Package managers | npm, pip, Homebrew, Maven, Playwright, node-gyp, `~/.cache`, `brew cleanup` | `node_modules` in projects untouched for 60+ days |
| JetBrains | Settings/caches of older IDE versions, IDE caches | — |
| Browsers & apps | Chrome, Opera, Firefox, Claude HTTP caches, other third-party caches | — |
| System | User logs, diagnostic reports, downloaded macOS updates, Trash | — |

Apple's own caches (`~/Library/Caches/com.apple.*`, CloudKit) are deliberately left alone.
Anything that doesn't exist on your Mac, or is smaller than 10 MB, is skipped.

## Customising

- **Project folders** scanned for stale `node_modules` are set near the
  `stale_nm=` line — change `~/dantweb ~/osc ~/PhpstormProjects` to wherever
  you keep your code (e.g. `~/Projects ~/Developer`).

## Notes

- The dry-run total is an upper bound: some items overlap.
- Docker's VM disk is only pruned when Docker Desktop is running. Otherwise use
  *Docker Desktop → Troubleshoot → Clean / Purge data*.
- After cleaning, empty the Trash and restart so macOS releases purgeable space.

## Disclaimer

This script deletes files. Review the prompts carefully, run `--dry-run` first,
and keep backups. Use at your own risk.

## License

[Boost Software License 1.0](LICENSE)

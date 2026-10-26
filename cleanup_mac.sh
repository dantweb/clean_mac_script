#!/bin/zsh
# Interactive macOS disk cleanup tailored to this machine.
# It never removes applications — only caches, build artifacts and dev data.
# Shows the size of every item and asks before removing it.
#
# Usage (run as your normal user, NOT with sudo — it asks for sudo only when needed):
#   ~/cleanup_mac.sh --dry-run    # show sizes, delete nothing
#   ~/cleanup_mac.sh              # ask y/N for each item
#   ~/cleanup_mac.sh --yes-safe   # auto-accept SAFE items (caches that regenerate), still ask for the rest
setopt null_glob extended_glob

DRY_RUN=0; YES_SAFE=0
for a in "$@"; do
  case "$a" in
    --dry-run|-n) DRY_RUN=1 ;;
    --yes-safe)   YES_SAFE=1 ;;
    *) echo "Unknown option: $a" >&2; exit 1 ;;
  esac
done

if [[ $EUID -eq 0 ]]; then
  echo "Run as your normal user (it will call sudo when needed)." >&2
  exit 1
fi

SIMCTL=/Applications/Xcode.app/Contents/Developer/usr/bin/simctl
[[ -x $SIMCTL ]] || SIMCTL="xcrun simctl"
TOTAL_KB=0

size_kb() { local s=0 k; for p in "$@"; do [[ -e "$p" ]] && { k=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); s=$((s + ${k:-0})); }; done; echo $s; }
human()   { awk -v k="$1" 'BEGIN{ if (k>=1048576) printf "%.1fG", k/1048576; else if (k>=1024) printf "%.0fM", k/1024; else printf "%dK", k }'; }

# ask LEVEL "description" KB  -> returns 0 if user agreed
ask() {
  local level=$1 desc=$2 kb=$3
  printf "\n[%s] %s  (%s)\n" "$level" "$desc" "$(human $kb)"
  if [[ $DRY_RUN -eq 1 ]]; then TOTAL_KB=$((TOTAL_KB + kb)); return 1; fi
  if [[ $YES_SAFE -eq 1 && $level == SAFE ]]; then echo "  -> auto-yes"; TOTAL_KB=$((TOTAL_KB + kb)); return 0; fi
  read -q "?  Remove? [y/N] " && { echo; TOTAL_KB=$((TOTAL_KB + kb)); return 0; }
  echo; return 1
}

# clean LEVEL "description" [--sudo] paths...   (removes the paths themselves)
clean() {
  local level=$1 desc=$2; shift 2
  local SUDO=""; [[ $1 == --sudo ]] && { SUDO=sudo; shift; }
  local existing=(); for p in "$@"; do [[ -e "$p" ]] && existing+=("$p"); done
  (( ${#existing} )) || return 0
  local kb=$(size_kb "${existing[@]}")
  (( kb > 10240 )) || return 0   # skip anything under 10 MB
  ask "$level" "$desc" $kb && $SUDO rm -rf -- "${existing[@]}"
}

echo "Free space before:"; df -h / | tail -1

echo "\n================ DEVELOPER: Xcode / iOS ================"
# Keep only the newest DeviceSupport folder; others are regenerated when a device is connected
DS=~/Library/Developer/Xcode/iOS\ DeviceSupport
old_ds=(); typeset -A seen
for d in "$DS"/*(N/om); do            # newest first
  model=${${d:t}%% *}                  # e.g. "iPhone15,3"
  if (( ${+seen[$model]} )); then old_ds+=("$d"); else seen[$model]=1; fi
done
clean SAFE "Old iOS DeviceSupport (keeps newest per device)" "${old_ds[@]}"
clean SAFE "Xcode DerivedData (build cache)"           ~/Library/Developer/Xcode/DerivedData
clean SAFE "Simulator dyld caches (regenerate)"        --sudo /Library/Developer/CoreSimulator/Caches
clean SAFE "Xcode/Swift caches"                        ~/Library/Caches/com.apple.dt.Xcode ~/Library/Caches/org.swift.swiftpm

if $=SIMCTL list >/dev/null 2>&1; then
  ask SAFE "Delete 'unavailable' simulators (no runtime left)" 0 && $=SIMCTL delete unavailable
  # Older simulator runtimes (keep the newest)
  runtimes=( ${(f)"$($=SIMCTL runtime list 2>/dev/null | grep -E '^iOS .* - [0-9A-F-]{36}' )"} )
  if (( ${#runtimes} > 1 )); then
    for line in "${runtimes[@]:1}"; do
      id=$(echo "$line" | grep -oE '[0-9A-F-]{36}')
      ask REVIEW "Old simulator runtime: ${line%% - *} (+ its simulators)" $((8 * 1048576)) && $=SIMCTL runtime delete "$id"
    done
  fi
  kb=$(size_kb ~/Library/Developer/CoreSimulator/Devices)
  ask REVIEW "Erase ALL simulator devices' data/apps (devices recreated empty)" $kb && { $=SIMCTL shutdown all; $=SIMCTL erase all; }
fi

echo "\n================ DEVELOPER: Android ================"
clean REVIEW "Android emulator images (~/.android/avd — recreate in Android Studio)" ~/.android/avd/*
clean REVIEW "Android SDK (~/Library/Android/sdk — needed by Android Studio)"         ~/Library/Android/sdk
clean SAFE   "Gradle caches"                                                          ~/.gradle/caches ~/.gradle/wrapper/dists

echo "\n================ DEVELOPER: Docker ================"
kb=$(size_kb ~/Library/Containers/com.docker.docker/Data/vms)
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  docker system df
  ask REVIEW "docker system prune -a --volumes (unused images, containers, volumes, build cache)" $((kb / 2)) \
    && docker system prune -a --volumes -f && docker builder prune -a -f
else
  printf "\n[INFO] Docker VM disk is %s. Start Docker Desktop and re-run to prune it,\n" "$(human $kb)"
  echo "       or Docker Desktop > Troubleshoot > 'Clean / Purge data' to reset it completely."
fi

echo "\n================ DEVELOPER: package caches ================"
clean SAFE "npm cache"               ~/.npm/_cacache
clean SAFE "pip cache"               ~/Library/Caches/pip
clean SAFE "Homebrew cache"          ~/Library/Caches/Homebrew
clean SAFE "Playwright browsers"     ~/Library/Caches/ms-playwright
clean SAFE "node-gyp / misc ~/.cache" ~/Library/Caches/node-gyp ~/.cache
clean SAFE "Maven repository cache"  ~/.m2/repository
command -v brew >/dev/null && ask SAFE "brew cleanup --prune=all (old formula versions)" 0 && brew cleanup --prune=all

# node_modules in projects untouched for 60+ days (reinstall with npm install)
stale_nm=( ${(f)"$(find ~/dantweb ~/osc ~/PhpstormProjects -name node_modules -type d -prune -mtime +60 2>/dev/null)"} )
clean REVIEW "node_modules in projects not touched for 60+ days (${#stale_nm} folders)" "${stale_nm[@]}"

echo "\n================ JetBrains ================"
# Old IDE versions' config/caches (keep newest per product)
JB=~/Library/Application\ Support/JetBrains
for product in PyCharm PhpStorm IntelliJIdea; do
  old=( "$JB"/${product}20*(N/On[2,-1]) ~/Library/Caches/JetBrains/${product}20*(N/On[2,-1]) ~/Library/Logs/JetBrains/${product}20*(N/On[2,-1]) )
  clean SAFE "Old $product versions' settings/caches (keeps newest)" "${old[@]}"
done
clean SAFE "JetBrains caches (indexes rebuild on next open)" ~/Library/Caches/JetBrains

echo "\n================ Browsers & app caches ================"
clean SAFE "Google Chrome cache"    ~/Library/Caches/Google
clean SAFE "Opera cache"            ~/Library/Caches/com.operasoftware.Opera
clean SAFE "Firefox cache"          ~/Library/Caches/Firefox
clean SAFE "Claude app HTTP cache"  ~/Library/Application\ Support/Claude/Cache ~/Library/Application\ Support/Claude/Code\ Cache
clean SAFE "Other third-party caches in ~/Library/Caches" \
  ~/Library/Caches/^(com.apple.*|CloudKit|Google|JetBrains|com.operasoftware.Opera|Firefox|pip|Homebrew|ms-playwright|node-gyp|org.swift.swiftpm|com.apple.dt.Xcode)

echo "\n================ Logs, Trash, updates ================"
clean SAFE "User logs"                     ~/Library/Logs/*
clean SAFE "System logs & diagnostics"     --sudo /Library/Logs/DiagnosticReports/* /private/var/log/asl/*.asl
clean SAFE "Downloaded macOS updates (/Library/Updates)" --sudo /Library/Updates/*
clean SAFE "Trash"                         ~/.Trash/*

echo "\n=========================================================="
if [[ $DRY_RUN -eq 1 ]]; then
  echo "Dry run: up to $(human $TOTAL_KB) could be freed if you said yes to everything. Nothing removed."
else
  echo "Selected roughly $(human $TOTAL_KB) for removal."
  echo "Free space after:"; df -h / | tail -1
  echo "Tip: empty the Trash and restart so macOS releases purgeable space."
fi

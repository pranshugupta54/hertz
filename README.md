# Hertz

A native macOS menu-bar system monitor. CPU, memory, disk, network, battery,
and a live process tree — read straight from the kernel, in one tidy dropdown.

Tiny, fast, no Electron. Built in Swift.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/pranshugupta54/hertz/main/install.sh | bash
```

That downloads the latest prebuilt release into `~/Applications`, launches it,
and it appears in your menu bar. No Xcode, no admin password.

From then on Hertz **keeps itself up to date** — it checks GitHub Releases on
launch and every 24 hours, and silently installs new versions.

## What it shows

- **CPU** — overall %, a live sparkline, per-core bars, load average, temperature
- **Memory** — used / free / swap, with a trend graph
- **Disk** — usage donut, free space, live read/write throughput, filesystem
- **Network** — up / down throughput, local IP, Wi-Fi SSID, VPN state
- **Battery** — charge, health, cycle count, temperature, adapter wattage
- **Processes** — a tree grouped by app, with subtree CPU/memory totals,
  sortable by CPU or memory
- **Health score** — a composite 0–100 at a glance
- Hardware header — chip, cores, RAM, macOS version, uptime

## How it works

Everything is read directly from the OS — no shelling out, no polling `top`:

- **CPU / memory** — Mach (`host_processor_info`, `host_statistics64`)
- **Processes** — `libproc` (`proc_listallpids`, `proc_pidinfo`, `proc_pid_rusage`)
- **Disk** — `statfs` + IOKit (`IOBlockStorageDriver`)
- **Battery** — IOKit power sources + the `AppleSmartBattery` registry
- **Temperature / fans** — the `AppleSMC` user client
- **Network** — `getifaddrs` + CoreWLAN

Per-process CPU and memory match Activity Monitor (CPU-time deltas converted
from Mach units; memory reported as physical footprint, not RSS).

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/pranshugupta54/hertz.git
cd hertz
swift run Hertz              # run it directly
./scripts/bundle.sh           # or build Hertz.app
```

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/pranshugupta54/hertz/main/uninstall.sh | bash
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Releases: [RELEASING.md](RELEASING.md).

## License

MIT — see [LICENSE](LICENSE).

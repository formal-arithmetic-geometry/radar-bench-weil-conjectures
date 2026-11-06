# radar-bench-weil-conjectures

The [radar](https://github.com/leanprover/radar) bench repo for
[weil-conjectures](https://github.com/formal-arithmetic-geometry/weil-conjectures).
Results: <https://radar.fuxi.merten.dev/repos/weil-conjectures>.

radar runs `bench.sh` on its runner for every commit it is asked to benchmark.
The script measures a clean `lake build` of weil-conjectures' own modules,
after setting up its dependencies without measuring them
(Mathlib from its olean cache, everything else built once and kept in `$RADAR_CACHE`).

## Metrics

From the measured `lake build` as a whole:

- `build//instructions`, `build//task-clock`, `build//wall-clock`, `build//maxrss`

Per module, from the `lean` wrapper in `fake-root/bin/lean`:

- `build/module/<module>//instructions`
- `build/module/<module>//lines`

Summed over all modules, from `lean --profile`:

- `build/profile/<category>//wall-clock` (elaboration, type checking, tactic execution, ...)

radar adds `radar/run/build//time` (the whole job) by itself.

## What is benchmarked, and when

Not every commit on master: master moves several hundred times a day and a clean build is
long. The server follows `refs/tags/radar/*` instead (one data point per tag), and
`!radar` in a PR comment benchmarks that PR against its merge base. The server config is
`fuxi/radar.nix` in chrisflav/nixos-config.

## Running the runner

The runner connects *out* to `https://radar.fuxi.merten.dev/api/`; it needs no inbound port.
It runs one job at a time and should have the machine to itself while it does, or the
numbers are noise.

Requirements on the runner machine:

- Java 25 (a JRE is enough), to run `radar.jar`
- [elan](https://github.com/leanprover/elan) on the runner user's `PATH`;
  `bench.sh` installs the right Lean toolchain through it
- `git`, `curl` (used by `lake exe cache get`), `python3` (3.12 or newer), coreutils
- `perf`, with `kernel.perf_event_paranoid` at 2 or lower so an unprivileged user can
  count its own instructions (`sysctl kernel.perf_event_paranoid=2`; Ubuntu defaults to 4)
- disk: roughly 15 GB for the runner's cache (two git clones, Mathlib's oleans, dependency
  builds) plus one build tree in its tmp directory

Build `radar.jar` from <https://github.com/leanprover/radar> with `./scripts/build`
(needs pnpm, Node, Maven and JDK 25), or ask for the jar fuxi builds.

`config-runner.yaml`, next to the jar:

```yaml
name: "bin"
url: "https://radar.fuxi.merten.dev/api/"
token: "<the runner token you were sent>"
# Free-form; stored with every run, so a hardware or OS change is visible in the data.
systemConfigurationId: "<hostname>, <cpu model>, <os>"
```

then

```sh
java -jar radar.jar runner config-runner.yaml
```

The runner keeps `cache/` and `tmp/` next to the config file unless told otherwise
(`--cache-dir`, `--tmp-dir`). A systemd unit for it:

```ini
[Unit]
Description=radar runner
After=network-online.target
Wants=network-online.target

[Service]
User=radar
WorkingDirectory=/var/lib/radar-runner
ExecStart=/usr/bin/java -jar /var/lib/radar-runner/radar.jar runner /var/lib/radar-runner/config-runner.yaml
# elan's toolchains, for the bench script
Environment=PATH=/var/lib/radar-runner/.elan/bin:/usr/local/bin:/usr/bin:/bin
Restart=always
RestartSec=30s

[Install]
WantedBy=multi-user.target
```

To try `bench.sh` without radar:

```sh
git clone https://github.com/formal-arithmetic-geometry/weil-conjectures /tmp/wc
RADAR_REPO=/tmp/wc RADAR_OUT=/tmp/out.jsonl RADAR_CACHE=/tmp/radar-cache ./bench.sh
```

## Provenance

`measure.py` and `fake-root/` are copied from Mathlib's benchmark suite,
[`scripts/bench`](https://github.com/leanprover-community/mathlib4/tree/2aa2784a4e62bc38be6695810788aacece56fd50/scripts/bench)
at 2aa2784, under the Apache License 2.0. `bench.sh` follows the shape of that suite's
`build/run`.

# WattOps PR energy check

A GitHub Action that measures the energy of a command on every pull request, compares it with the
base branch and comments the result, the way coverage bots comment on coverage:

> ### ⚡ Energy check
> ❌ **+17.9%**, over the 10% budget
>
> | | energy (median of 3) | range | time |
> |---|---|---|---|
> | this change `190cc69` | **41.2 J** | 40.8 J – 42.0 J | 3.10 s |
> | base `main` | 34.9 J | 34.1 J – 35.6 J | 2.71 s |

## Use it

`.github/workflows/energy.yml`:

```yaml
name: energy
on: pull_request
permissions:
  contents: read
  pull-requests: write   # to comment
jobs:
  energy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - uses: bsharma173860-oss/joules-action@v1
        with:
          setup: pip install -e .
          command: python benchmarks/run.py
          budget: 10        # fail when energy grows more than 10%
```

| input | default | |
|---|---|---|
| `command` | (required) | what to measure, run with bash |
| `setup` | | prepares each checkout, e.g. `pip install -e .` |
| `working-directory` | `.` | where to run |
| `runs` / `warmup` | `3` / `0` | runs per side; the medians are compared |
| `budget` | | percent growth that fails the check |
| `comment` | `true` | one comment per pull request, updated on each push |
| `project` + `api-key` | | also chart every result on your [Tracking page](https://landauer-gap.vercel.app/#/track) |

Outputs: `energy-j`, `base-energy-j`, `change-pct`, `over-budget`.

## Measured or estimated

On a machine with energy counters (a self-hosted runner with an NVIDIA, AMD or Intel GPU, or Linux
with RAPL) the joules are **measured**. GitHub's hosted runners are virtual machines without
counters, so there the energy is **estimated from CPU time** (3 W per busy core; set `JOULES_CPU_W`)
and the comment says so. The estimate is steady between runs, which is what catches regressions.

A difference smaller than the run-to-run spread is reported as noise and never fails the check.

Runs the same check locally: `joules ci --base main --budget 10 -- pytest -q`

For a budget on a *planned* training run (estimated kWh or CO₂ before you pay for it), see the
[energy budget action](../github-action/action.yml).

## Estimate a workload instead

`bsharma173860-oss/joules-action/estimate@v1` posts a workload's estimated electricity, CO₂ and cost
(from the WattOps API) and fails the check when it goes over a budget:

```yaml
      - uses: bsharma173860-oss/joules-action/estimate@v1
        with:
          api-key: ${{ secrets.LANDAUER_API_KEY }}
          inputs: '{"params": 8, "tokens": 1, "count": 8}'
          budget-kwh: 5000
```

WattOps (formerly Landauer Gap): https://landauer-gap.vercel.app · joules on PyPI: https://pypi.org/project/landauer-gap/

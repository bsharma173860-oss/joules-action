#!/usr/bin/env bash
# Landauer Gap GitHub Action. Inputs come only through environment variables (never spliced
# into the script), so workflow inputs cannot inject shell commands.
set -euo pipefail

if [ -z "${LG_KEY:-}" ]; then
  echo "::error title=Landauer Gap::No API key. Create one at https://landauer-gap.vercel.app/#/settings/keys, add it in this repository under Settings → Secrets and variables → Actions as LANDAUER_API_KEY, and pass it as api-key: \${{ secrets.LANDAUER_API_KEY }}"
  exit 1
fi
LG_URL="${LG_URL:-https://landauer-gap.vercel.app}"
out="${GITHUB_OUTPUT:-/dev/null}"
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [ -n "${LG_INPUTS_FILE:-}" ]; then body="$(cat "$LG_INPUTS_FILE")"; else body="${LG_INPUTS:-{\}}"; fi
if ! jq -e 'type == "object"' >/dev/null 2>&1 <<<"$body"; then
  echo "::error title=Landauer Gap::inputs must be a JSON object, e.g. {\"params\":70,\"tokens\":15000}"
  exit 1
fi

call() { # path, output file
  curl -sS --retry 2 --max-time 60 -o "$2" -w '%{http_code}' -X POST "$LG_URL$1" \
    -H "Authorization: Bearer $LG_KEY" -H "Content-Type: application/json" -H "User-Agent: landauer-gap-action/1" \
    --data "$body"
}

code="$(call /api/v1/estimate "$tmp/est.json")"
if [ "$code" != "200" ]; then
  msg="$(jq -r '.error.message // "request failed"' "$tmp/est.json" 2>/dev/null || echo "request failed")"
  fields="$(jq -r '[.error.fields[]? | "\(.field): \(.message)"] | join("; ")' "$tmp/est.json" 2>/dev/null || true)"
  echo "::error title=Landauer Gap (HTTP $code)::$msg${fields:+ — $fields}"
  exit 1
fi

r() { jq -r "$1" "$tmp/est.json"; }
# 62690.4 -> 62,690 ; 0.1234 -> 0.123
num() { awk -v x="$1" 'BEGIN { if (x >= 100) { s = sprintf("%.0f", x); n = length(s); o = ""; for (i = 1; i <= n; i++) { o = o substr(s, i, 1); if ((n - i) % 3 == 0 && i < n) o = o "," } print o } else printf "%.3g\n", x }'; }
kwh="$(r '.results.energy_kwh.facility')"
co2="$(r '.results.co2_tonnes')"
cost="$(r '.results.cost.amount')"
cur="$(r '.results.cost.currency')"
gap="$(r '.results.landauer_gap')"
mode="$(r '.mode')"
label="$(r '.label')"
{
  echo "energy-kwh=$kwh"; echo "co2-tonnes=$co2"; echo "cost=$cost"; echo "landauer-gap=$gap"
} >> "$out"

per=""; [ "$mode" = "inference" ] && per=" / year"
{
  echo "### ⚡ Landauer Gap — $label"
  echo
  echo "| Electricity$per | CO₂$per | Cost$per | Landauer gap |"
  echo "|---|---|---|---|"
  printf '| %s kWh | %s t | %s %s | %s× |\n' "$(num "$kwh")" "$(num "$co2")" "$(num "$cost")" "${cur^^}" "$(printf '%.2e' "$gap")"
  echo
  echo "**Cheapest ways to close the gap**"
  echo
  echo "| Change | Energy | CO₂ | CO₂ saved |"
  echo "|---|---|---|---|"
  jq -r '.results.close_the_gap[:4][] | "| \(.change) | \(.energy_kwh | floor) kWh | \(.co2_tonnes * 1000 | floor / 1000) t | \(.co2_saved_fraction * 1000 | floor / 10)% |"' "$tmp/est.json"
} >> "$summary"

fail=0
over() { awk -v a="$1" -v b="$2" 'BEGIN { exit !(a > b) }'; }
if [ -n "${LG_BUDGET_KWH:-}" ] && over "$kwh" "$LG_BUDGET_KWH"; then
  echo "::error title=Energy budget exceeded::$(num "$kwh") kWh is over the budget of $LG_BUDGET_KWH kWh"; fail=1
fi
if [ -n "${LG_BUDGET_CO2:-}" ] && over "$co2" "$LG_BUDGET_CO2"; then
  echo "::error title=Carbon budget exceeded::$(printf '%.3g' "$co2") t CO2 is over the budget of $LG_BUDGET_CO2 t"; fail=1
fi
if [ -n "${LG_BUDGET_KWH:-}${LG_BUDGET_CO2:-}" ]; then
  { echo; [ "$fail" = 0 ] && echo "✅ Within budget" || echo "❌ Over budget"; echo "(${LG_BUDGET_KWH:+$LG_BUDGET_KWH kWh}${LG_BUDGET_KWH:+${LG_BUDGET_CO2:+, }}${LG_BUDGET_CO2:+$LG_BUDGET_CO2 t CO2})"; } >> "$summary"
fi

if [ "${LG_REPORT:-false}" = "true" ]; then
  dest="${RUNNER_TEMP:-$tmp}/landauer-gap-report.pdf"
  code="$(call /api/v1/report "$dest")"
  if [ "$code" = "200" ]; then
    echo "report-path=$dest" >> "$out"
    echo "📄 PDF report saved to \`$dest\`" >> "$summary"
  else
    echo "::warning title=Landauer Gap report::$(jq -r '.error.message // "report failed"' "$dest" 2>/dev/null || echo "report failed") (HTTP $code)"
  fi
fi

echo "Landauer Gap: $label — $(num "$kwh") kWh, $(num "$co2") t CO2, gap $(printf '%.2e' "$gap")x"
exit "$fail"

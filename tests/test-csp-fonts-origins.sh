#!/usr/bin/env bash
# =============================================================================
# test-csp-fonts-origins.sh — pins that the generated nginx CSP ships WITHOUT
# the Google Fonts origins (self-hosted fonts, ADR-001/006).
#
# setup/setup-server.sh renders the site config for BOTH branches: HTTPS (with
# HSTS) and plain HTTP (initial setup, no cert). One policy is generated per
# branch, so the origins have to be gone from BOTH — tightening only one leaves
# the other still telling the browser to fetch Sora from Google.
#
# COUPLING: this ships TOGETHER WITH the frontend's self-hosted-Sora change
# (other repo/PR). Dropping the origins alone breaks Sora in internet-connected
# environments, where nothing serves the font locally yet.
#
# Run: bash bs_deploy/tests/test-csp-fonts-origins.sh
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_SH="$SCRIPT_DIR/../setup/setup-server.sh"

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok    %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  %s\n     esperado: %s\n     obtenido: %s\n' "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# The quoted value of every Content-Security-Policy add_header in the generator.
mapfile -t POLICIES < <(grep -oE 'Content-Security-Policy "[^"]*"' "$SETUP_SH" \
  | sed -e 's/^Content-Security-Policy "//' -e 's/"$//')

# Directive body of a policy: everything after its name (e.g. font-src -> "'self'").
directive() { # <policy> <name>
  printf '%s' "$1" | tr ';' '\n' \
    | sed -e 's/^ *//' -e 's/ *$//' \
    | sed -n "s/^$2 //p"
}

echo "CSP del sitio generado — origenes de fuentes"

# Both branches must be covered by the sweep below.
check "el generador define dos policies (HTTPS + HTTP)" "2" "${#POLICIES[@]}"

for i in "${!POLICIES[@]}"; do
  p="${POLICIES[$i]}"
  n=$((i + 1))

  # The fonts are self-hosted, so style-src must carry no external origin at
  # all (only 'self' + the loader hash) and font-src must collapse to 'self'.
  # Asserted generically -- this test deliberately does NOT hardcode the Google
  # domains, so it never becomes a stray hit for the sweep that forbids them.
  check "policy #$n: style-src sin ningun origen externo" "" \
    "$(directive "$p" style-src | grep -o '[a-z][a-z0-9+.-]*://[^ ]*' || true)"
  check "policy #$n: style-src conserva 'self' y el hash del loader" "yes" \
    "$(directive "$p" style-src | grep -q "'self'" \
       && directive "$p" style-src | grep -q "'sha256-" && echo yes || echo no)"

  check "policy #$n: font-src queda en 'self'" "'self'" \
    "$(directive "$p" font-src)"

  # A dropped source must not leave a dangling, source-less directive behind.
  check "policy #$n: ninguna directiva quedo vacia" "" \
    "$(printf '%s' "$p" | tr ';' '\n' | sed -e 's/^ *//' -e 's/ *$//' | awk 'NF < 2 { print }')"

  # CSP source lists are single-quoted tokens: the quote count must stay even.
  check "policy #$n: comillas simples balanceadas" "0" \
    "$(( $(printf '%s' "$p" | tr -cd "'" | wc -c) % 2 ))"

  # The tightened policy still declares the full directive set.
  for d in default-src script-src style-src img-src font-src connect-src \
           frame-src frame-ancestors base-uri object-src form-action; do
    check "policy #$n: conserva $d" "yes" \
      "$([[ -n "$(directive "$p" "$d")" ]] && echo yes || echo no)"
  done
done

echo
printf 'ok: %d   fallos: %d\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]

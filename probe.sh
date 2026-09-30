#!/bin/sh
# Probe auth.na.gndctl.com (Keycloak) from GitHub Actions clean egress.
# app.na gave 403 from Azure; auth.na untested. >=2s pacing per program rules.
set -u
case "$(node -v 2>/dev/null)" in
  v18*) ;;
  *) echo "skip: matrix job $(node -v)"; exit 0 ;;
esac

A="https://auth.na.gndctl.com"
G="$A/realms/gndctl"
P() { sleep 2; }

echo "### RUNNER EGRESS IP"
curl -sS -m 15 https://api.ipify.org || true
echo ""

echo "### 1 discovery"
curl -sS -m 25 -D- -o /tmp/d.json "$G/.well-known/openid-configuration" || echo "FAIL $?"
echo "body_head=$(head -c 120 /tmp/d.json 2>/dev/null)"
echo "----"
P

echo "### 2 client registration (JSON, expected 401 if token required)"
curl -sS -m 25 -D- -o /tmp/r.json -X POST -H 'Content-Type: application/json' \
  -d '{"client_id":"ghacteprobe1","client_name":"research","redirect_uris":["https://evil.example/cb"]}' \
  "$G/clients-registrations/openid-connect" || echo "FAIL $?"
echo "body=$(head -c 400 /tmp/r.json 2>/dev/null)"
echo "----"
P

echo "### 3 token endpoint bad creds (error shape)"
curl -sS -m 25 -D- -o /tmp/t.json -X POST -H 'Content-Type: application/x-www-form-urlencoded' \
  -d 'grant_type=password&client_id=account&username=probe&password=probe' \
  "$G/protocol/openid-connect/token" || echo "FAIL $?"
echo "body=$(head -c 300 /tmp/t.json 2>/dev/null)"
echo "----"
P

echo "### 4 admin root"
curl -sS -m 25 -D- -o /tmp/a.json "$A/admin/" || echo "FAIL $?"
echo "body_head=$(head -c 200 /tmp/a.json 2>/dev/null)"
echo "----"
P

echo "### 5 realm admin API (expect 401 json)"
curl -sS -m 25 -D- -o /tmp/ad.json "$A/admin/realms/gndctl" || echo "FAIL $?"
echo "body=$(head -c 300 /tmp/ad.json 2>/dev/null)"
echo "----"
P

echo "### 6 auth endpoint GET (client_id=account, redirect app.na)"
curl -sS -m 25 -D- -o /tmp/au.html -w 'code=%{http_code} final=%{url_effective}\n' \
  "$G/protocol/openid-connect/auth?client_id=account&redirect_uri=https%3A%2F%2Fapp.na.gndctl.com%2F&scope=openid&response_type=code" || echo "FAIL $?"
echo "body_head=$(head -c 300 /tmp/au.html 2>/dev/null)"
echo "----"
P

echo "### 7 userinfo unauth"
curl -sS -m 25 -D- -o /tmp/ui.json "$G/protocol/openid-connect/userinfo" || echo "FAIL $?"
echo "body=$(head -c 200 /tmp/ui.json 2>/dev/null)"
echo "----"
P

echo "### 8 registration with GH source header (Origin reflect check)"
curl -sS -m 25 -D- -o /dev/null -X OPTIONS -H 'Origin: https://evil.example' \
  -H 'Access-Control-Request-Method: POST' -H 'Access-Control-Request-Headers: content-type' \
  "$G/clients-registrations/openid-connect" || echo "FAIL $?"
echo "----"
P

echo "### DONE"

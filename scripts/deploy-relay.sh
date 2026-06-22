#!/usr/bin/env bash
#
# Deploy the SecureChat relay to the Lenovo (212.186.18.125).
#
# Mirrors loupe-signaling/scripts/.../deploy.sh:
#   1. SSH-test (Pitfall: rsync vom Hermes-Rechner hängt manchmal transient)
#   2. rsync RelayServer/ -> /opt/securechat/ (kein Git auf Server)
#   3. docker compose build --no-cache + up -d --no-deps
#      (Docker-Pitfall: up allein nimmt das alte Image, build erzwingt
#      Dockerfile-Re-Evaluation)
#   4. Smoke-Tests: healthz, /v1/relay/security/policy, /v1/relay/stats
#      (kein auth), /healthz/internal ohne Token = 401
#
# Build identifiers werden via GIT_SHA + BUILD_VERSION ARG durchgereicht
# und in /healthz sichtbar. Wird in der Build-Version mit "+" konkateniert,
# exakt wie bei Loupe.
#
# Usage:
#   ./scripts/deploy-relay.sh                    # default: HEAD + v0.1.0
#   ./scripts/deploy-relay.sh --tag v0.2.0       # explizite Build-Version
#   ./scripts/deploy-relay.sh --no-build         # nur rsync + restart
#   ./scripts/deploy-relay.sh --dry-run          # zeigt was passieren würde

set -euo pipefail

# ----- Config -----
SSH_HOST="miggu69@212.186.18.125"
REMOTE_DIR="/opt/securechat"
LOCAL_REPO="$(cd "$(dirname "$0")/.." && pwd)"
RELAY_DIR="$LOCAL_REPO/RelayServer"

BUILD_VERSION="0.1.0"
GIT_SHA="$(git -C "$LOCAL_REPO" rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
DO_BUILD=1
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)        BUILD_VERSION="$2"; shift 2 ;;
    --no-build)   DO_BUILD=0; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    --git-sha)    GIT_SHA="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown flag: $1" >&2
      exit 1
      ;;
  esac
done

# ----- 1. Sanity -----
echo ">> Local relay dir:  $RELAY_DIR"
echo ">> Remote dir:       $REMOTE_DIR"
echo ">> Git SHA:          $GIT_SHA"
echo ">> Build version:    $BUILD_VERSION"
echo ">> Build?            $DO_BUILD"
echo ">> Dry run?          $DRY_RUN"
echo

if [[ ! -d "$RELAY_DIR" ]]; then
  echo "ERROR: $RELAY_DIR does not exist" >&2
  exit 1
fi

if [[ ! -f "$RELAY_DIR/Dockerfile" ]]; then
  echo "ERROR: Dockerfile missing in $RELAY_DIR" >&2
  exit 1
fi

if [[ -f "$RELAY_DIR/.env" ]]; then
  echo "WARN: $RELAY_DIR/.env exists locally. It is NOT rsynced to the"
  echo "      server (the server has its own .env with the real tokens)."
fi

# ----- 2. SSH check (transient-hang-Pitfall von Loupe gelernt) -----
echo ">> SSH probe"
if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_HOST" 'echo "ok: $(date)"' 2>&1 | head -1 | grep -q "ok:"; then
  echo "ERROR: SSH to $SSH_HOST did not respond. Re-trying once after 5s..."
  sleep 5
  if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$SSH_HOST" 'echo ok' >/dev/null 2>&1; then
    echo "ERROR: SSH still failing. Check the server / network." >&2
    exit 1
  fi
fi
echo "   SSH OK"
echo

# ----- 3. rsync (Punkt 3: --delete nur für die relay-eigenen Files, NICHT /data) -----
echo ">> rsync relay -> $SSH_HOST:$REMOTE_DIR"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "   (dry-run: would rsync RelayServer/ except .env, node_modules, dist)"
else
  # .env NICHT überschreiben (Server hat andere Token!).
  # node_modules + dist werden auf dem Server via Dockerfile gebaut.
  rsync -avz --exclude='.env' --exclude='node_modules' --exclude='dist' \
    --exclude='*.log' --exclude='data/' \
    "$RELAY_DIR/" "$SSH_HOST:$REMOTE_DIR/" 2>&1 | tail -5
fi
echo

# ----- 4. Build & restart -----
# The relay's publicVersion() function formats the final version
# string as `${BUILD_VERSION}+${GIT_SHA}`, so BUILD_VERSION must be
# the semver prefix (e.g. "0.1.0") and GIT_SHA the short commit.
# Passing "0.1.0+0cd0b07" as BUILD_VERSION would produce
# "0.1.0+0cd0b07+0cd0b07" in /healthz.
COMPOSE_BUILD_VERSION="$BUILD_VERSION"
COMPOSE_GIT_SHA="$GIT_SHA"
# Distinct image tag per deploy so the previous image is preserved
# for one quick `docker compose down && up` rollback. The compose
# file's `image:` line is patched to match.
IMAGE_TAG="securechat-relay:${GIT_SHA}"
if [[ $DO_BUILD -eq 1 ]]; then
  echo ">> patch /opt/securechat/docker-compose.yml image: $IMAGE_TAG"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "   (dry-run: would sed-replace 'image: securechat-relay:.*' -> 'image: $IMAGE_TAG')"
  else
    ssh -o ConnectTimeout=30 -o BatchMode=yes "$SSH_HOST" \
      "cd $REMOTE_DIR && \
       sed -i.bak -E 's#image: securechat-relay:.*#image: $IMAGE_TAG#' docker-compose.yml && \
       grep '^    image:' docker-compose.yml"
  fi
  echo
  echo ">> docker compose build (multi-stage, --no-cache)"
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "   (dry-run: would run"
    echo "    cd $REMOTE_DIR &&"
    echo "    GIT_SHA=$GIT_SHA BUILD_VERSION=$BUILD_VERSION \\"
    echo "    docker compose build --no-cache)"
  else
    ssh -o ConnectTimeout=30 -o BatchMode=yes "$SSH_HOST" \
      "cd $REMOTE_DIR && \
       GIT_SHA='$COMPOSE_GIT_SHA' \
       BUILD_VERSION='$COMPOSE_BUILD_VERSION' \
       docker compose build --no-cache" 2>&1 | tail -8
  fi
  echo
fi

echo ">> docker compose up -d --no-deps (Coturn-Äquivalent: securechat bleibt es nur ein Container)"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "   (dry-run: would run"
  echo "    cd $REMOTE_DIR &&"
  echo "    GIT_SHA=$GIT_SHA BUILD_VERSION=$BUILD_VERSION \\"
  echo "    docker compose up -d --no-deps)"
else
  ssh -o ConnectTimeout=30 -o BatchMode=yes "$SSH_HOST" \
    "cd $REMOTE_DIR && \
     GIT_SHA='$COMPOSE_GIT_SHA' \
     BUILD_VERSION='$COMPOSE_BUILD_VERSION' \
     docker compose up -d --no-deps" 2>&1 | tail -5
fi
echo

# ----- 5. Smoke-Tests -----
if [[ $DRY_RUN -eq 1 ]]; then
  echo ">> (dry-run: skipping smoke tests)"
  exit 0
fi

echo ">> wait 5s for the container to start"
sleep 5
echo

echo ">> smoke: public /healthz"
HEALTHZ=$(curl -sS --max-time 5 https://securechat.team/healthz 2>&1 || true)
if [[ -z "$HEALTHZ" ]]; then
  # domain probably not yet pointed at this server; try the public hostname
  # that the operator is currently using
  HEALTHZ=$(curl -sS --max-time 5 https://chatsecure.ddns.net/healthz 2>&1 || true)
fi
echo "   $HEALTHZ"
if ! echo "$HEALTHZ" | grep -q '"status":"ok"'; then
  echo "WARN: /healthz did not return a healthy response. The container"
  echo "      may still be starting, or the public hostname is not yet"
  echo "      pointed at this server."
fi
echo

echo ">> smoke: /healthz/internal ohne Token (sollte 401 sein)"
INT_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 https://chatsecure.ddns.net/healthz/internal 2>&1 || true)
if [[ "$INT_STATUS" != "401" ]]; then
  # try securechat.team
  INT_STATUS=$(curl -sS -o /dev/null -w "%{http_code}" --max-time 5 https://securechat.team/healthz/internal 2>&1 || true)
fi
echo "   HTTP $INT_STATUS"
if [[ "$INT_STATUS" != "401" && "$INT_STATUS" != "503" ]]; then
  echo "WARN: /healthz/internal without token should be 401 (or 503 if the"
  echo "      operator hasn't set OPS_TOKEN yet), got $INT_STATUS."
fi
echo

echo ">> smoke: /v1/relay/security/policy (sollte 200 mit JSON sein)"
POLICY=$(curl -sS --max-time 5 https://chatsecure.ddns.net/v1/relay/security/policy 2>&1 || true)
if [[ -z "$POLICY" ]]; then
  POLICY=$(curl -sS --max-time 5 https://securechat.team/v1/relay/security/policy 2>&1 || true)
fi
echo "   $(echo "$POLICY" | head -c 200)"
echo
if ! echo "$POLICY" | grep -q '"encryptedPayloadOnly":true'; then
  echo "WARN: /v1/relay/security/policy did not return the expected shape."
fi

echo
echo ">> Done. The relay is running build $BUILD_VERSION+$GIT_SHA."
echo "   Public healthz: https://securechat.team/healthz"
echo "   Public site:    https://securechat.team/"
echo "   Status:         https://securechat.team/status.html"

#!/usr/bin/env bash
# Install a Firebase service-account key for push notifications.
#
# The credential MUST come from the same Firebase project the app is built
# against, otherwise every send fails with PermissionDenied (project gone /
# key revoked) or SenderIdMismatch (tokens minted by a different project).
#
#   Usage: ./install_firebase_credential.sh ~/Downloads/nexaround-e9a5e-xxxx.json
#
# Get the file from: Firebase console -> Project settings -> Service accounts
#                    -> Generate new private key
set -euo pipefail

SRC="${1:-}"
DEST=/etc/nexaround/firebase-sa.json
PLIST=/var/www/nexaround/nexaround_app/ios/Runner/GoogleService-Info.plist

if [ -z "$SRC" ] || [ ! -f "$SRC" ]; then
  echo "usage: $0 <service-account.json>" >&2
  exit 1
fi

# The project the app is actually built against.
EXPECTED=$(sed -n '/<key>PROJECT_ID<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$PLIST")
ACTUAL=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['project_id'])" "$SRC")

echo "app project:        $EXPECTED"
echo "credential project: $ACTUAL"

if [ "$EXPECTED" != "$ACTUAL" ]; then
  echo "REFUSING: credential is for a different Firebase project than the app." >&2
  echo "Download the key from project '$EXPECTED' instead." >&2
  exit 1
fi

install -m 600 -o root -g root "$SRC" "$DEST"
echo "installed -> $DEST"

cd /var/www/nexaround/nexaround_backend
docker compose restart api
echo "api restarted. Confirm with:"
echo "  docker logs --tail 50 nexaround_backend-api-1 2>&1 | grep 'FCM initialised'"

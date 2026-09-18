#!/bin/bash
# Compiles MailAvatarSync and installs it where Mail's "Run AppleScript" rule can find it.
set -euo pipefail

DEST="$HOME/Library/Application Scripts/com.apple.mail"
SRC="$(cd "$(dirname "$0")" && pwd)/MailAvatarSync.applescript"

mkdir -p "$DEST"

if [ -f "$DEST/MailAvatarSync.scpt" ]; then
  BACKUP="$DEST/MailAvatarSync.scpt.bak-$(date +%Y%m%d%H%M%S)"
  cp "$DEST/MailAvatarSync.scpt" "$BACKUP"
  echo "Backed up existing script to: $BACKUP"
fi

osacompile -o "$DEST/MailAvatarSync.scpt" "$SRC"
echo "Installed: $DEST/MailAvatarSync.scpt"
echo
echo "Next steps:"
echo "  1. Quit and reopen Mail (it caches the compiled script)."
echo "  2. Mail > Settings > Rules > Add Rule > Perform Action: Run AppleScript > MailAvatarSync"
echo "  3. Approve the prompt letting Mail control Contacts."
echo "  4. Watch it work:  tail -f ~/Library/Logs/MailAvatarSync.log"

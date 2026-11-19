#!/bin/sh
# Start one idle claude through the Inari label wrapper, for 5 minutes, so the
# label can be checked by eye in Activity Monitor. Claude exits when sleep ends
# and its stdin closes. Uses no tokens: no message is ever sent.
cd "$HOME/vaults/the-akashic-records/tools/inari" || exit 1
sleep 300 | INARI_PROC_LABEL=label-test bin/claude-labeled \
  --output-format stream-json --verbose --input-format stream-json --safe-mode >/dev/null 2>&1

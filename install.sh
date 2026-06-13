#!/usr/bin/env bash
# install.sh — Install persona-deploy-doctor systemd user units
# Does NOT auto-enable; prints the enable command for the user to run.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

echo "Installing persona-deploy-doctor systemd user units..."
mkdir -p "$SYSTEMD_USER_DIR"

install -Dm644 "$SCRIPT_DIR/persona-deploy-doctor.service" \
    "$SYSTEMD_USER_DIR/persona-deploy-doctor.service"
install -Dm644 "$SCRIPT_DIR/persona-deploy-doctor.timer" \
    "$SYSTEMD_USER_DIR/persona-deploy-doctor.timer"

systemctl --user daemon-reload

echo ""
echo "Units installed. To enable and start the daily drift check, run:"
echo ""
echo "  systemctl --user enable --now persona-deploy-doctor.timer"
echo ""
echo "To run a one-shot check right now:"
echo ""
echo "  systemctl --user start persona-deploy-doctor.service"
echo "  journalctl --user -u persona-deploy-doctor.service -e"
echo ""
echo "Or run directly:"
echo ""
echo "  $SCRIPT_DIR/doctor.sh --expect-self-name Clara"

#!/bin/sh

# Minimal live desktop: Openbox window manager + PCManFM desktop icons.
# No panel, app store, terminal shortcut, or extra user-facing tools.
unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

if command -v dbus-launch >/dev/null 2>&1; then
  eval "$(dbus-launch --sh-syntax --exit-with-session)"
fi

xset -dpms
xset s off
xset s noblank

exec openbox-session

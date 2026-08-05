# Auto-start the only graphical desktop on the first virtual console.
if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = /dev/tty1 ]; then
  exec startx -- -nolisten tcp vt1
fi

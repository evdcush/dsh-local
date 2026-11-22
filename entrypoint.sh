#!/bin/sh
# DeepSeek Harness container launcher.
#
# 1. Seed the web profile definition into $DSH_HOME on first start. Existing
#    files are never touched, so later edits (UI or file) survive restarts.
# 2. Bind the listener to the container's own bridge address. dsh's
#    webserver accepts one concrete local address and refuses wildcard
#    binds; the bridge IP is what the host port mapping reaches.
# 3. Forward the optional public-URL and trusted-host settings.

set -eu

PROFILE_DIR="$DSH_HOME/profiles/web"
mkdir -p "$PROFILE_DIR"
for f in package.json cordis.patch.yml; do
  if [ ! -f "$PROFILE_DIR/$f" ]; then
    cp "/opt/dsh/profile/web/$f" "$PROFILE_DIR/$f"
  fi
done

HOST_IP="$(hostname -i | awk '{print $1}')"

set -- --profile web --no-open --host "$HOST_IP" --port "${DSH_PORT:-3080}"

# Optional tailscale-style exposure: advertised URL plus browser authorities.
if [ -n "${DSH_PUBLIC_URL:-}" ]; then
  set -- "$@" --public-url "$DSH_PUBLIC_URL"
fi
if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
  OLD_IFS=$IFS
  IFS=','
  for host in $DSH_TRUSTED_HOSTS; do
    IFS=$OLD_IFS
    case "$host" in
      [!\ ]*) [ -n "$host" ] && set -- "$@" --trusted-host "$host" ;;
    esac
    IFS=','
  done
  IFS=$OLD_IFS
fi

exec dsh "$@"

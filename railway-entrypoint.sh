#!/bin/sh
# Railway entrypoint for Tailscale: sets containerboot's environment, then keeps it
# running. When containerboot gives up (nobody logged in yet, a rejected auth key, a
# setting it refuses), this says why and tries again in the same container, instead of
# exiting: a crash loop restarts ten times, then leaves a dead deploy with the reason buried.
set -u
say() { echo "[railway] $*"; }

# Railway containers have no /dev/net/tun, so tailscaled runs its userspace network
# stack. Exit node and subnet routes work there.
export TS_USERSPACE=true
# The node's keys live on the volume, so a redeploy is the same machine, not a new one.
export TS_STATE_DIR="${TS_STATE_DIR:-/var/lib/tailscale}"
mkdir -p "$TS_STATE_DIR"
state="$TS_STATE_DIR/tailscaled.state"
# Log in only when there is no saved login. Auth keys are often single-use or expire,
# and logging in again with a spent key on every restart would knock the node offline.
export TS_AUTH_ONCE=true
export TS_SOCKET=/tmp/tailscaled.sock

# containerboot passes TS_EXTRA_ARGS to the first `tailscale up` only; once logged in it
# runs `tailscale set`, which ignores them. So the exit node is also set by the watcher
# below every time the node comes up, and turning TS_EXIT_NODE off takes effect.
case "${TS_EXIT_NODE:-true}" in true|1|yes) exit_node=true ;; *) exit_node=false ;; esac
args="${TS_EXTRA_ARGS:-}"
[ "$exit_node" = true ] && args="$args --advertise-exit-node"
if [ -n "${TS_LOGIN_SERVER:-}" ]; then args="$args --login-server=$TS_LOGIN_SERVER"; fi
export TS_EXTRA_ARGS="$args"

# Offer the project's private network to the tailnet, so a laptop can reach other
# services at their railway.internal addresses. Routes only take effect once approved
# in the admin console. IPv4 is the network of the private interface, IPv6 is fd12::/16.
routes="${TS_ROUTES:-}"
case "${TS_RAILWAY_ROUTES:-true}" in
  true|1|yes)
    v4=$(ip -o -4 addr show dev railnet0 2>/dev/null | awk '{
      split($4, a, "/"); split(a[1], o, "."); bits = a[2]; ip = 0
      for (i = 1; i <= 4; i++) ip = ip * 256 + o[i]
      size = 1; for (i = bits; i < 32; i++) size *= 2
      net = int(ip / size) * size
      for (i = 4; i >= 1; i--) { q = int(net / 256); b[i] = net - q * 256; net = q }
      printf "%d.%d.%d.%d/%d\n", b[1], b[2], b[3], b[4], bits
      exit }')
    for r in $v4 fd12::/16; do routes="${routes:+$routes,}$r"; done
    ;;
esac
export TS_ROUTES="$routes"

logged_in() { [ -s "$state" ] && grep -q '_current-profile' "$state"; }
has_key() { [ -n "${TS_AUTHKEY:-}${TS_AUTH_KEY:-}${TS_CLIENT_ID:-}" ]; }

# No key: tailscale waits for someone to open a login link. containerboot gives that
# 60 seconds, then exits, so give it a week instead.
if ! logged_in && ! has_key; then
  export TS_BOOT_TIMEOUT="${TS_BOOT_TIMEOUT:-168h}"
  say "No TS_AUTHKEY set: open the login link below to add this node to your tailnet."
fi

boot=
stopping=
trap 'stopping=1; [ -n "$boot" ] && kill -TERM "$boot" 2>/dev/null' TERM INT

# The watcher. When the node is up, it applies the exit node setting. While nobody
# has logged in, it repeats the login link, which tailscale prints once among dozens
# of log lines: every minute for the first 10, then every 10 minutes.
(
  n=0; applied=
  while true; do
    sleep 15
    st=$(tailscale --socket="$TS_SOCKET" status --json 2>/dev/null) || { applied=; continue; }
    case "$st" in
      *'"BackendState": "Running"'*)
        n=0
        if [ -z "$applied" ]; then
          tailscale --socket="$TS_SOCKET" set --advertise-exit-node="$exit_node" \
            && say "Tailscale is up. Exit node: $exit_node." && applied=1
        fi
        continue ;;
      *'"BackendState": "NeedsLogin"'*) applied= ;;
      *) applied=; n=0; continue ;;
    esac
    url=$(printf '%s\n' "$st" | sed -n 's/.*"AuthURL": "\([^"]*\)".*/\1/p' | head -1)
    [ -n "$url" ] || continue
    if [ $((n % 4)) -eq 0 ] && { [ $n -lt 40 ] || [ $((n % 40)) -eq 0 ]; }; then
      say "Log in to add this node to your tailnet: $url"
    fi
    n=$((n + 1))
  done
) &
watcher=$!

delay=30
while true; do
  say "starting Tailscale as ${TS_HOSTNAME:-(container hostname)}, routes: ${TS_ROUTES:-none}, extra args:${TS_EXTRA_ARGS:- none}"
  /usr/local/bin/containerboot &
  boot=$!
  rc=0
  wait "$boot" || rc=$?
  # wait returns early when the trap runs; wait again for containerboot to finish.
  wait "$boot" 2>/dev/null || true
  [ -n "$stopping" ] && { kill "$watcher" 2>/dev/null; exit 0; }

  if ! logged_in && has_key; then
    say "Tailscale couldn't log in with TS_AUTHKEY: the key is wrong, already used, or expired (or TS_LOGIN_SERVER or TS_EXTRA_ARGS is wrong; the reason is above). Make a new auth key in the Tailscale admin console (Settings > Keys), put it in TS_AUTHKEY, and redeploy. Or clear TS_AUTHKEY and log in with the link this prints."
  elif ! logged_in; then
    say "Tailscale stopped before anyone logged in. Trying again for a new login link."
  else
    say "Tailscale stopped (exit $rc); the reason is in the lines above. A setting it refuses, such as TS_ROUTES or TS_EXTRA_ARGS, needs fixing in Variables."
  fi
  say "Retrying in $delay seconds."
  sleep "$delay" & wait $! 2>/dev/null
  [ -n "$stopping" ] && { kill "$watcher" 2>/dev/null; exit 0; }
  delay=$((delay * 2)); [ $delay -gt 900 ] && delay=900
done

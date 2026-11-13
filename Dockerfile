# Tailscale for Railway: the official image plus a small entrypoint that maps the
# template's variables onto containerboot and keeps the node's identity on the volume.
FROM tailscale/tailscale:v1.104.7
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 755 /usr/local/bin/railway-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]

# Deploy and Host Tailscale on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/tailscale-vpn?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=tailscale-vpn)

Tailscale is a mesh VPN built on WireGuard: your devices join one private network, a tailnet, wherever they are. This template adds a Railway machine to your tailnet. It does two jobs: an exit node, so your phone or laptop can browse from Railway's IP in the region you choose, and a subnet router, so your devices can reach this project's private services, such as a database, by their `railway.internal` names without exposing them to the internet.

This is a community template, not made or supported by Tailscale.

## About Hosting Tailscale

Tailscale's official image runs on Railway, but not cleanly. Railway containers have no TUN device, so it has to run Tailscale's userspace network stack. Without an auth key, `tailscale up` waits for a login, and the container gives up after 60 seconds and crash-loops. A single-use key fails on every restart after the first. And a node without a volume becomes a new machine on each redeploy.

This template handles those. It runs in userspace mode, keeps the node's identity on a volume, logs in only once, and waits as long as you need for a login.

**Log in:** deploy, open the service's **Deploy Logs**, and open the line `Log in to add this node to your tailnet: https://login.tailscale.com/a/...`. It repeats until you use it. Or put an auth key from the admin console (Settings > Keys) in `TS_AUTHKEY` before deploying.

**Use it as an exit node:** in the [admin console](https://login.tailscale.com/admin/machines), open the machine's menu, choose **Edit route settings**, and tick **Use as exit node**. Then pick it as the exit node on any device. Traffic leaves from the region set in the service's **Settings > Regions**.

**Reach your Railway services:** in the same **Edit route settings**, approve the two subnet routes (an IPv4 `10.x.0.0/9` range and `fd12::/16`). For names, go to **DNS > Add nameserver > Custom**, enter `fd12::10`, turn on **Restrict to domain**, and enter `railway.internal`. Then, from any device on your tailnet, `postgres.railway.internal:5432` works the way it does inside Railway.

## Common Use Cases

- A personal VPN exit node in the US, EU or Asia, for public Wi-Fi or to browse from another region
- Connecting your laptop to a private Railway database, Redis or internal API without a public TCP proxy
- Giving a team private access to staging services through Tailscale's access controls

## Dependencies for Tailscale Hosting

- A Tailscale account (the free plan works), or a Headscale server

### Deployment Dependencies

- [Tailscale documentation](https://tailscale.com/kb)
- [Exit nodes](https://tailscale.com/kb/1103/exit-nodes) and [subnet routers](https://tailscale.com/kb/1019/subnets)
- [Template source](https://github.com/two-workspaces/tailscale)

### Implementation Details

- **Tested on Railway** (with a Headscale control server, since it needs no account): the node joins from an auth key; a second device routes through it as an exit node and appears on the internet from Railway's IP; that device reaches another service in the project by `railway.internal` name, IPv4 and IPv6; redeploys keep the same machine; turning `TS_EXIT_NODE` off and on takes effect on redeploy; without a key the login link repeats past the point where the stock image gives up; a bad key logs a message and retries instead of crash-looping. Peers connected directly, not through a relay. Logging in through login.tailscale.com was reached but not completed.
- **Memory:** about 35 MB, so it runs on any plan, including Free.
- **Bandwidth:** exit node traffic counts as Railway network egress, which Railway bills per GB.
- **Key expiry:** Tailscale expires a machine's login after 180 days by default. Turn off key expiry for this machine in the admin console so it stays connected.
- **Settings after the first login:** `TS_HOSTNAME`, `TS_EXIT_NODE` and the routes apply on every deploy. `TS_EXTRA_ARGS` and `TS_LOGIN_SERVER` apply only to the first login; to change them later, delete the volume's contents or use `tailscale set` in the service's shell.
- **Headscale:** set `TS_LOGIN_SERVER` to your Headscale URL. If Headscale itself runs on Railway, give it a TCP proxy and use `http://host:port` from that: Railway's HTTPS domains drop the `Upgrade` header that Tailscale's control protocol needs.
- **Image:** `ghcr.io/two-workspaces/tailscale`, built from this repository's Dockerfile on `tailscale/tailscale:v1.104.7`.

## Why Deploy Tailscale on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Tailscale on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.

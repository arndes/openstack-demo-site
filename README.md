# openstack-demo-site

A bootable qcow2 disk image (Ubuntu 24.04) ready for OpenStack Glance. The instance runs nginx and serves a live dashboard displaying server and client network information.

## What it looks like

The dashboard shows three info cards (server address, hostname, local clock) and a client-IP strip. Values refresh automatically via a configurable polling interval. Dark/light theme toggle is persisted in `localStorage`.

## Requirements

```bash
sudo apt install qemu-utils libguestfs-tools qemu-system-x86 wget
```

## Build

```bash
make                         # produces openstack-demo.qcow2 (~4 GB)
make IMAGE=my.qcow2 SIZE=8G  # custom output name and disk size
make clean                   # removes the image
```

The first run downloads the Ubuntu 24.04 cloud base image (~600 MB) and caches it at `~/.cache/ubuntu-cloud-images/`. Subsequent builds reuse the cache.

> **Requires `sudo`** — libguestfs needs read access to `/boot/vmlinuz-*`.

### Build variables

| Variable | Default | Description |
|----------|---------|-------------|
| `IMAGE`  | `openstack-demo.qcow2` | Output filename |
| `SIZE`   | `4G` | Disk size |
| `ROOTPW` | `demo` | Root password injected into the image |

## Local preview (no build needed)

```bash
./preview.sh          # serves web/ on port 8080 and opens the browser
PORT=3000 ./preview.sh
```

Starts a Python mock server that mimics the nginx `/info` endpoint. Press Ctrl+C to stop.

## Test the built image locally

```bash
qemu-system-x86_64 -m 512 -drive file=openstack-demo.qcow2,format=qcow2 \
  -netdev user,id=net0,hostfwd=tcp::8080-:80 -device virtio-net,netdev=net0 \
  -nographic
```

Open `http://localhost:8080`. Login: `root` / `demo`.

## Upload to OpenStack

```bash
openstack image create \
  --file openstack-demo.qcow2 \
  --disk-format qcow2 \
  --container-format bare \
  openstack-demo
```

## How it works

### Build pipeline

```
wget (Ubuntu cloud image)
  └─ qemu-img convert   — re-encode as qcow2
       └─ qemu-img resize  — expand disk to SIZE
            └─ virt-customize
            │     ├─ growpart /dev/sda 1 + resize2fs  — expand root partition
            │     ├─ enable root login (cloud-init override)
            │     ├─ install nginx
            │     ├─ copy web/index.html → /var/www/html/
            │     ├─ copy nginx/default → /etc/nginx/sites-available/
            │     └─ enable + start nginx
            ├─ virt-sysprep  — seal the image
            └─ virt-sparsify — reclaim unused blocks
```

### `/info` endpoint

nginx returns a JSON object built from built-in variables — no backend process required:

```json
{
  "client_ip":   "203.0.113.42",
  "server_addr": "10.0.0.5",
  "server_port": "80",
  "hostname":    "demo-vm",
  "request_uri": "/info"
}
```

The frontend fetches this endpoint on load and on every auto-refresh tick, then updates the cards in place without a full page reload.

## Project layout

```
web/index.html      Single-file frontend (HTML + CSS + JS, no build step)
nginx/default       nginx vhost config deployed to /etc/nginx/sites-available/
Makefile            Drives the full build pipeline
preview.sh          Local dev server — serves web/ and mocks /info
```

## Notes

- **cloud-init stays enabled** — it handles interface naming (`ens3`, etc.) and DHCP on first boot in OpenStack. Root login is enabled via `/etc/cloud/cloud.cfg.d/99-root.cfg`.
- **Do not use `virt-builder`** — Ubuntu 24.04 is not available there (max 20.04).
- **Do not run `sgdisk` on the qcow2** — it expects raw format and corrupts the image. `growpart` handles GPT header repair inside `virt-customize`.
- Ubuntu 24.04 cloud image partition layout: `sda1` = root, `sda14` = BIOS boot, `sda15` = EFI, `sda16` = /boot.

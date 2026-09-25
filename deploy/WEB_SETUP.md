# Web version setup (one time)

Browsers on an `https://` page only allow secure `wss://` connections. Caddy
sits in front of the Godot server, adds HTTPS, and also serves the web client.
The game ends up at **https://64-225-2-31.sslip.io**.

## 1. On your Mac: install web export templates
Godot → Editor → Manage Export Templates → Download and Install.

## 2. On the server (ssh gamestudio@64.225.2.31)

```bash
# Install Caddy (Ubuntu/Debian)
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install -y caddy

# Folder for the web client, writable by you
sudo mkdir -p /var/www/mmorpg
sudo chown gamestudio:gamestudio /var/www/mmorpg

# Open HTTP/HTTPS if the firewall is on
sudo ufw allow 80/tcp && sudo ufw allow 443/tcp
```

Also allow ports 80 and 443 in the DigitalOcean cloud firewall, if you use one.

## 3. Install the Caddy config (from your Mac, in the project folder)

```bash
scp deploy/Caddyfile gamestudio@64.225.2.31:~/Caddyfile
ssh gamestudio@64.225.2.31 'sudo mv ~/Caddyfile /etc/caddy/Caddyfile && sudo systemctl reload caddy'
```

## 4. Deploy the web client

```bash
./deploy_web.sh
```

Then open https://64-225-2-31.sslip.io. The game server itself must be running
(`./deploy_server.sh`). Desktop clients keep working on `ws://64.225.2.31:8080`.

## Testing locally
Export the Web preset, serve `exports/web` with any static server, run the
game server locally, and open e.g.
`http://localhost:8000/?server=ws://127.0.0.1:8080`.

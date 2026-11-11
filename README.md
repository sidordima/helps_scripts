# helps_scripts
Useful scripts to make my life easier.

## Contents
- [porkbun_ssl](#porkbun_ssl)

---

## porkbun_ssl

Automated SSL certificate retrieval and renewal via the Porkbun API, featuring expiration checking and post-update service hooks (Nginx, HAProxy, Docker, etc.).

### Features
- **Expiration Check**: Checks certificate validity before contacting the API (renews only when remaining days fall below threshold).
- **Safe Updates**: Existing certificates are never overwritten if API request or validation fails.
- **Post-update Hooks**: Executes custom commands upon renewal (e.g., syntax test, service reload, certificate bundle creation).
- **Dependency Auto-install**: Checks for and installs `curl`, `jq`, and `openssl` if missing.

### Setup

1. Copy the configuration template:
   ```bash
   cp porkbun_ssl/example.config.env porkbun_ssl/config.env
   ```

2. Edit `porkbun_ssl/config.env` with your domain, Porkbun API keys, and post-update commands:
   - `DOMAIN`: Domain name configured in Porkbun.
   - `API_KEY` & `SECRET_KEY`: Porkbun API credentials.
   - `POST_COMMANDS`: List of bash commands to execute after certificate renewal.

3. Make the script executable:
   ```bash
   chmod +x porkbun_ssl/down_cert.sh
   ```

4. Perform a test run:
   ```bash
   ./porkbun_ssl/down_cert.sh
   ```

### Crontab Setup

To run daily certificate renewal checks automatically, add a cron entry.

Since renewing certificates often requires writing to protected directories (`/root/certs`, `/etc/ssl/`) and reloading system services (`systemctl reload nginx`), open the root crontab:

```bash
sudo crontab -e
```

Add the scheduled task (runs every day at 03:00 AM):

```cron
0 3 * * * /path/to/helps_scripts/porkbun_ssl/down_cert.sh >> /var/log/porkbun_ssl.log 2>&1
```

> **Note:** Replace `/path/to/helps_scripts` with the absolute path to your repository (e.g., `/home/sidor/helps_scripts`).

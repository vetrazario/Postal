# SSL/TLS Setup Guide

This guide explains how to enable HTTPS and SMTP TLS for the Email Sender Infrastructure.

## 📋 Prerequisites

Before starting, ensure:

1. **Domain DNS** - Your domain must point to the server's IP address
2. **Firewall** - Ports 80 and 443 must be accessible from the internet
3. **Services Running** - Docker containers must be running
4. **Email** - You need a valid email address for Let's Encrypt notifications

## 🔐 What Will Be Configured

### HTTPS (Port 443)
- **Let's Encrypt SSL certificates** for your domain
- **Auto-renewal** every 12 hours via certbot container
- **HTTP to HTTPS redirect** for all traffic (except health checks and ACME challenges)
- **Security headers** (HSTS, X-Frame-Options, etc.)

### SMTP TLS (Port 2587)
- **STARTTLS support** for encrypted SMTP connections from AMS Enterprise
- **Same Let's Encrypt certificates** used for HTTPS
- **Automatic fallback** to non-TLS if certificates are not available

## 🚀 Quick Setup

### Step 1: Run SSL Setup Script

```bash
cd /opt/email-sender
sudo bash scripts/setup-ssl.sh
```

The script will:
1. Check DNS configuration
2. Obtain Let's Encrypt certificates
3. Update nginx configuration
4. Reload nginx with HTTPS enabled
5. Configure auto-renewal

### Step 2: Rebuild Services

After obtaining certificates, rebuild the smtp-relay container to enable TLS:

```bash
cd /opt/email-sender
docker compose build smtp-relay
docker compose up -d smtp-relay
```

### Step 3: Verify Setup

Check HTTPS:
```bash
curl https://linenarrow.com/health
```

Check SMTP TLS:
```bash
docker compose logs smtp-relay | grep TLS
```

You should see: `✓ TLS certificates found and loaded`

## 📝 Manual Setup (Alternative)

If the automatic script doesn't work, follow these manual steps:

### 1. Obtain Certificates Manually

```bash
cd /opt/email-sender

# Get certificates using certbot container
docker compose run --rm certbot certonly \
    --webroot \
    --webroot-path=/var/www/certbot \
    --email admin@linenarrow.com \
    --agree-tos \
    --no-eff-email \
    --force-renewal \
    -d linenarrow.com
```

### 2. Update nginx Configuration

Edit `config/nginx.conf` and replace `DOMAIN` placeholder:

```bash
sed -i "s|/etc/letsencrypt/live/DOMAIN/|/etc/letsencrypt/live/linenarrow.com/|g" config/nginx.conf
```

### 3. Reload nginx

```bash
docker compose exec nginx nginx -t  # Test configuration
docker compose exec nginx nginx -s reload  # Reload
```

### 4. Rebuild SMTP Relay

```bash
docker compose build smtp-relay
docker compose up -d smtp-relay
```

## 🔍 Verification

### Check Certificate Details

```bash
# View certificate expiration
openssl s_client -connect linenarrow.com:443 -servername linenarrow.com < /dev/null 2>/dev/null | openssl x509 -noout -dates

# View certificate issuer
openssl s_client -connect linenarrow.com:443 -servername linenarrow.com < /dev/null 2>/dev/null | openssl x509 -noout -issuer
```

### Test HTTPS Endpoints

```bash
# Dashboard
curl -I https://linenarrow.com/dashboard

# API Health
curl https://linenarrow.com/health

# API endpoint (requires authentication)
curl https://linenarrow.com/api/v1/emails
```

### Test SMTP STARTTLS

```bash
# Connect and test STARTTLS
openssl s_client -connect linenarrow.com:2587 -starttls smtp

# Or using telnet
telnet linenarrow.com 2587
# Then type: EHLO test
# Should see: 250-STARTTLS
```

### Check Logs

```bash
# nginx logs
docker compose logs nginx | tail -50

# smtp-relay logs (should show TLS enabled)
docker compose logs smtp-relay | grep -i tls

# certbot logs
docker compose logs certbot
```

## 🔄 Certificate Renewal

Certificates are automatically renewed by the certbot container every 12 hours.

### Manual Renewal

If you need to renew manually:

```bash
docker compose run --rm certbot renew
docker compose exec nginx nginx -s reload
docker compose restart smtp-relay
```

### Check Renewal Cron

The certbot container runs this command every 12 hours:
```bash
certbot renew
```

## 🛠️ Troubleshooting

### Problem: Certificate Validation Failed

**Symptoms:** certbot returns error "Failed authorization procedure"

**Solution:**
1. Verify DNS: `dig +short linenarrow.com` should return your server IP
2. Verify port 80 is accessible: `curl http://linenarrow.com/.well-known/acme-challenge/test`
3. Check nginx is running: `docker compose ps nginx`
4. Check firewall: `sudo ufw status` or `sudo iptables -L`

### Problem: nginx Won't Start with SSL

**Symptoms:** nginx container exits immediately after enabling SSL

**Solution:**
1. Check certificate files exist:
   ```bash
   docker compose exec nginx ls -la /etc/letsencrypt/live/linenarrow.com/
   ```
2. Test nginx configuration:
   ```bash
   docker compose exec nginx nginx -t
   ```
3. Check nginx error logs:
   ```bash
   docker compose logs nginx | grep error
   ```

### Problem: SMTP TLS Not Working

**Symptoms:** smtp-relay logs show "TLS certificates not found"

**Solution:**
1. Verify certificates are mounted:
   ```bash
   docker compose exec smtp-relay ls -la /etc/letsencrypt/live/linenarrow.com/
   ```
2. Check DOMAIN environment variable:
   ```bash
   docker compose exec smtp-relay printenv DOMAIN
   ```
3. Rebuild smtp-relay:
   ```bash
   docker compose build smtp-relay
   docker compose up -d smtp-relay
   ```

### Problem: HTTP Still Works (No Redirect)

**Symptoms:** Can access http://linenarrow.com instead of being redirected to HTTPS

**Solution:**
This is expected for:
- `/.well-known/acme-challenge/*` (needed for certificate renewal)
- `/health` (needed for monitoring)

All other traffic should redirect to HTTPS.

## 🔒 Security Notes

### SSL/TLS Settings

The nginx configuration uses:
- **Protocols:** TLSv1.2, TLSv1.3 (no TLSv1.0/1.1)
- **Ciphers:** HIGH:!aNULL:!MD5
- **HSTS:** Enabled with 1 year max-age

### SMTP TLS Settings

The SMTP relay uses:
- **STARTTLS:** Optional (not enforced)
- **Certificates:** Same as HTTPS (Let's Encrypt)
- **Port:** 2587 (external) → 587 (internal)

### Certificate Security

- Certificates stored in Docker volume `certbot_certs`
- Mounted read-only to nginx and smtp-relay
- Auto-renewed every 12 hours
- 90-day expiration (Let's Encrypt default)

## 📚 Files Modified

This setup modifies/adds these files:

1. **config/nginx.conf** - Added HTTPS server block and HTTP redirect
2. **docker-compose.yml** - Updated nginx and smtp-relay volume mounts
3. **services/smtp-relay/server.js** - Added TLS certificate detection and STARTTLS support
4. **scripts/setup-ssl.sh** - New script for automated SSL setup

## 🎯 Next Steps After Setup

1. **Test email sending** through SMTP with TLS enabled
2. **Configure AMS Enterprise** to use STARTTLS on port 2587
3. **Set up monitoring** for certificate expiration
4. **Configure backups** to include certificates (optional)

## 📞 Support

If you encounter issues:
1. Check logs: `docker compose logs`
2. Verify DNS: `dig linenarrow.com`
3. Test ports: `nc -zv linenarrow.com 80 443 2587`
4. Review this troubleshooting guide

## ✅ Success Checklist

- [ ] HTTPS enabled and working
- [ ] HTTP redirects to HTTPS
- [ ] SSL certificate valid and issued by Let's Encrypt
- [ ] SMTP relay shows "TLS: ENABLED" in logs
- [ ] STARTTLS available in SMTP (test with `EHLO`)
- [ ] Auto-renewal configured in certbot container
- [ ] All services healthy: `docker compose ps`

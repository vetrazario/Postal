# ✅ Email Tracking Setup Checklist

## Pre-Deployment

- [ ] Pull latest changes: `git pull origin claude/bounce-patterns-management-Awt4F`
- [ ] Review changes: `git log --oneline -10`
- [ ] Check current branch: `git branch`

## Deployment

- [ ] Run migrations: `docker compose exec api rails db:migrate`
- [ ] Rebuild containers: `docker compose build api sidekiq`
- [ ] Restart services: `docker compose up -d --force-recreate --no-deps api sidekiq`
- [ ] Wait 20 seconds: `sleep 20`
- [ ] Check status: `docker compose ps api sidekiq`

## Configuration

- [ ] Open Dashboard: https://linenarrow.com/dashboard/tracking_settings
- [ ] Configure tracking:
  - [ ] Click Tracking: **ON** (readable redirects)
  - [ ] Open Tracking: **ON** (Gmail-optimized pixel)
  - [ ] Max Tracked Links: **10** (track all links)
  - [ ] Privacy Footer: **ON**
  - [ ] Daily Send Limit: **500**
  - [ ] Branded Domain: **go.linenarrow.com** (optional)

## Domain Reputation

- [ ] Check domain reputation
- [ ] Verify SPF record exists: `dig TXT linenarrow.com +short | grep spf`
- [ ] Verify DKIM configured: `dig TXT default._domainkey.linenarrow.com +short`
- [ ] Verify DMARC policy: `dig TXT _dmarc.linenarrow.com +short`
- [ ] Check blacklist status: должно быть `blacklisted: false`
- [ ] Reputation score > 75

## DNS Setup (if not configured)

- [ ] Add SPF record:
  ```
  linenarrow.com. TXT "v=spf1 a mx ip4:YOUR_IP ~all"
  ```
- [ ] Add DMARC record:
  ```
  _dmarc.linenarrow.com. TXT "v=DMARC1; p=quarantine; rua=mailto:dmarc@linenarrow.com"
  ```
- [ ] DKIM: автоматически настроен Postal

## Testing

- [ ] Send test campaign with link
- [ ] Check received email - link format: `/go/youtube-video-abc12345`
- [ ] Click link - should do fast 301 redirect to destination
- [ ] Check Dashboard Analytics - click should be recorded
- [ ] Verify no "tracking warning" in Gmail
- [ ] Check privacy footer appears
- [ ] Test bot detection - bot clicks shouldn't be tracked
- [ ] Verify repeat clicks don't duplicate stats

## Warmup (for new domains only)

- [ ] Domain age < 30 days?
  - [ ] YES: Enable warmup mode
  - [ ] NO: Skip

## Post-Deployment Monitoring

- [ ] Check throttling info: `docker compose exec api rails runner "puts EmailThrottler.throttle_info"`
- [ ] Monitor click rate: Dashboard → Analytics
- [ ] Check spam complaints: должно быть < 0.3%
- [ ] Review logs for errors: `docker compose logs api sidekiq --tail=50`

## Optional: Branded Domain

- [ ] Create subdomain: `go.linenarrow.com` → A record → SERVER_IP
- [ ] Get SSL cert: `certbot certonly --standalone -d go.linenarrow.com`
- [ ] Configure in Dashboard: Tracking Domain = `go.linenarrow.com`
- [ ] Test branded link

## Daily Checks

- [ ] Reputation score > 75
- [ ] Not blacklisted
- [ ] Spam rate < 0.3%
- [ ] Click rate > 2%
- [ ] Throttle quota not exceeded

---

## Quick Commands

```bash
# Pull changes
git pull origin claude/bounce-patterns-management-Awt4F

# Deploy
docker compose exec api rails db:migrate
docker compose build api sidekiq
docker compose up -d --force-recreate --no-deps api sidekiq

# Check status
docker compose ps
docker compose logs api sidekiq --tail=50

# Check reputation
curl https://linenarrow.com/dashboard/tracking_settings/check_reputation | jq

# Check throttling
docker compose exec api rails runner "puts EmailThrottler.throttle_info"

# Enable warmup
docker compose exec api rails runner "EmailThrottler.enable_warmup!"

# Disable warmup
docker compose exec api rails runner "EmailThrottler.disable_warmup!"
```

---

**Estimated Time:** 15-20 minutes
**Difficulty:** Medium
**Required Access:** SSH, Dashboard, DNS

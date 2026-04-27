#!/usr/bin/env bash
# recon-vps.sh — Read-only audit of shared-VPS state.
# RUNS ON VPS. Produces output suitable for docs/foundation/infrastructure-state-day-3.md.
# NO writes, no restarts, no destructive ops.

set -euo pipefail

echo "=== Operscale Video Ads — VPS Recon ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ==="
echo ""

echo "## 1. Docker containers"
docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || echo "  ⚠️  docker not reachable"
echo ""

echo "## 2. n8n container health"
if docker ps --format '{{.Names}}' | grep -q '^n8n-n8n-1$'; then
  docker exec n8n-n8n-1 ffmpeg -version 2>&1 | head -1 || true
  docker exec n8n-n8n-1 ls /tmp 2>&1 | head -10 || true
  docker exec n8n-n8n-1 env 2>&1 | grep -E '^NODE_FUNCTION_ALLOW_BUILTIN|^DB_' || echo "  (no relevant env)"
else
  echo "  ❌ n8n-n8n-1 not running"
fi
echo ""

echo "## 3. Caption burn service"
systemctl status caption-burn.service --no-pager 2>&1 | head -10 || echo "  ⚠️  systemd unit not found"
curl -sf -o /dev/null -w "  health-check HTTP: %{http_code}\n" http://172.18.0.1:9998/health || \
    echo "  ⚠️  caption-burn /health not reachable on 172.18.0.1:9998"
echo ""

echo "## 4. Filesystem layout"
ls -la /data/ 2>/dev/null | head -20 || echo "  ⚠️  /data not readable"
ls -la /docker/ 2>/dev/null | head -20 || echo "  ⚠️  /docker not readable"
echo ""

echo "## 5. Supabase containers"
docker ps --format '{{.Names}}' | grep -i supabase || echo "  ⚠️  no supabase containers"
echo ""

echo "## 6. Postgres tables (count only, no data)"
if docker ps --format '{{.Names}}' | grep -q supabase-db-1; then
  docker exec supabase-db-1 psql -U postgres -t -c \
    "SELECT count(*) AS table_count FROM information_schema.tables WHERE table_schema='public';" 2>&1 || true
else
  echo "  ⚠️  supabase-db-1 not running"
fi
echo ""

echo "## 7. Realtime publication"
if docker ps --format '{{.Names}}' | grep -q supabase-db-1; then
  docker exec supabase-db-1 psql -U postgres -t -c \
    "SELECT tablename FROM pg_publication_tables WHERE pubname='supabase_realtime' ORDER BY tablename;" 2>&1 || true
fi
echo ""

echo "## 8. Traefik routes (if accessible)"
docker ps --format '{{.Names}}' | grep -i traefik || echo "  (traefik container not visible by name)"
echo ""

echo "## 9. Disk + memory"
df -h / 2>/dev/null | head -2 || true
free -h 2>/dev/null | head -3 || true
echo ""

echo "=== Recon complete ==="

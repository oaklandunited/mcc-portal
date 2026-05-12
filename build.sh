#!/usr/bin/env bash
# Generates config.js from environment variables at build time (Vercel / Netlify).
# Locally, you create config.js by hand from config.example.js — this script is
# only for deploys, so config.js stays out of git.

set -euo pipefail

: "${SUPABASE_URL:?SUPABASE_URL env var is required}"
: "${SUPABASE_ANON_KEY:?SUPABASE_ANON_KEY env var is required}"

cat > config.js <<EOF
// Auto-generated at build time. Do not edit.
window.SUPABASE_URL = '${SUPABASE_URL}';
window.SUPABASE_ANON_KEY = '${SUPABASE_ANON_KEY}';
EOF

echo "Generated config.js for ${SUPABASE_URL}"

# Snapshot-ID deiner Instanz in Hetzner ermitteln (Beispiel: 12345678)
SNAPSHOT_ID="424302367"

# Provider-Label setzen
curl -X PUT "https://api.hetzner.cloud/v1/images/${SNAPSHOT_ID}" \
  -H "Authorization: Bearer $HCLOUD_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"labels":{"caph-image-name":"flatcar-stable-x86","channel":"stable","os":"flatcar"}}'

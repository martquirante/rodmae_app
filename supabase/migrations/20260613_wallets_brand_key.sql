-- Add brand_key column to wallets if not already present
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS brand_key VARCHAR;
ALTER TABLE wallets ADD COLUMN IF NOT EXISTS name      VARCHAR;

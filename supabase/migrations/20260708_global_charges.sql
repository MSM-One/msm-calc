-- ================================================================
-- MSM Calc: global_charges migration
-- Run this in: Supabase Dashboard -> SQL Editor
-- ================================================================

CREATE TABLE IF NOT EXISTS global_charges (
  id         TEXT PRIMARY KEY DEFAULT 'singleton',
  gst_rate   NUMERIC(5,2)  NOT NULL DEFAULT 18.00,
  lc_rate    NUMERIC(8,2)  NOT NULL DEFAULT 255.00,
  nc_discount NUMERIC(10,2) NOT NULL DEFAULT 3000.00,
  updated_at TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Seed the one singleton row
INSERT INTO global_charges (id, gst_rate, lc_rate, nc_discount)
VALUES ('singleton', 18.00, 255.00, 3000.00)
ON CONFLICT (id) DO NOTHING;

-- Enable Row Level Security
ALTER TABLE global_charges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read charges"  ON global_charges;
CREATE POLICY "Anyone can read charges"
  ON global_charges FOR SELECT USING (true);

DROP POLICY IF EXISTS "Admin can update charges" ON global_charges;
CREATE POLICY "Admin can update charges"
  ON global_charges FOR UPDATE USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS "Admin can insert charges" ON global_charges;
CREATE POLICY "Admin can insert charges"
  ON global_charges FOR INSERT WITH CHECK (true);

SELECT * FROM global_charges;

-- Also add rate, rec_qty, and region columns to transactions table for Vendor Purchase/Sauda
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS rate NUMERIC(12,2) DEFAULT 0.0;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS rec_qty NUMERIC(12,3) DEFAULT 0.000;
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS region TEXT;

-- Add nc_discount to global_charges (if upgrading existing table)
ALTER TABLE global_charges ADD COLUMN IF NOT EXISTS nc_discount NUMERIC(10,2) NOT NULL DEFAULT 3000.00;

-- Add size_difference to item_sizes for per-size SD configuration
ALTER TABLE item_sizes ADD COLUMN IF NOT EXISTS size_difference NUMERIC(10,2) NOT NULL DEFAULT 0.00;

-- Verify
SELECT id, gst_rate, lc_rate, nc_discount FROM global_charges;
SELECT id, material_id, size_label, size_difference FROM item_sizes LIMIT 5;


-- Migration: Add is_sample_rate_active flag to item_sizes for Sample Rate benchmarks
ALTER TABLE item_sizes ADD COLUMN IF NOT EXISTS is_sample_rate_active BOOLEAN DEFAULT false;

-- Seed/Set the default 18 MS Pipe benchmarks to true (material_id = 1)
UPDATE item_sizes 
SET is_sample_rate_active = true 
WHERE material_id = 1 AND id IN (2, 5, 9, 15, 20, 21, 25, 28, 32, 37, 48, 52, 56, 60, 63, 67, 73, 77);

-- Seed default benchmarks for MS Angle (material_id = 2)
UPDATE item_sizes
SET is_sample_rate_active = true
WHERE material_id = 2 AND id IN (88, 89, 90, 93, 94, 95, 98, 100);

-- Seed default benchmarks for MS Channel (material_id = 3)
UPDATE item_sizes
SET is_sample_rate_active = true
WHERE material_id = 3 AND id IN (105, 106, 107);

-- Seed default benchmarks for Sqr Bar (material_id = 6)
UPDATE item_sizes
SET is_sample_rate_active = true
WHERE material_id = 6 AND id IN (115, 116);

-- Seed default benchmarks for Round Bar (material_id = 7)
UPDATE item_sizes
SET is_sample_rate_active = true
WHERE material_id = 7 AND id IN (119, 120, 121);

-- Seed default benchmarks for Flats (material_id = 8)
UPDATE item_sizes
SET is_sample_rate_active = true
WHERE material_id = 8 AND id IN (123, 126, 127, 129);

-- ============================================================================
-- MIGRATION: 002_reporting_views.sql
-- DESCRIPTION: High-performance Postgres Reporting Views with Security Invoker
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

-- 1. Master Current Stock View (v_current_stock)
-- Combines base item_sizes.current_stock_in (mapped to 'YARD') + live transaction balances
DROP VIEW IF EXISTS public.v_low_stock CASCADE;
DROP VIEW IF EXISTS public.v_non_moving_stock CASCADE;
DROP VIEW IF EXISTS public.v_current_stock CASCADE;

CREATE OR REPLACE VIEW public.v_current_stock 
WITH (security_invoker = true) AS
WITH base_sizes AS (
  SELECT 
    s.id AS size_id,
    s.material_id,
    COALESCE(m.item_name, 'General Material') AS item_name,
    s.size_label,
    COALESCE(s.current_stock_in, 0) AS opening_stock
  FROM public.item_sizes s
  LEFT JOIN public.materials m ON m.id = s.material_id
),
txn_totals AS (
  SELECT 
    t.material_id,
    t.size_id,
    COALESCE(UPPER(t.location), 'YARD') AS location,
    SUM(
      CASE 
        WHEN UPPER(t.txn_type) IN ('IN', 'RETURN', 'ADJUSTMENT', 'OPENING') OR UPPER(t.type) IN ('IN', 'RETURN', 'ADJUSTMENT', 'OPENING') THEN COALESCE(t.qty_mt, 0)
        WHEN UPPER(t.txn_type) IN ('OUT', 'RESERVE') OR UPPER(t.type) IN ('OUT', 'RESERVE') THEN -COALESCE(t.qty_mt, 0)
        ELSE 0
      END
    ) AS txn_net
  FROM public.transactions t
  WHERE COALESCE(t.is_reversed, false) = false
  GROUP BY t.material_id, t.size_id, COALESCE(UPPER(t.location), 'YARD')
),
all_locations AS (
  SELECT size_id, material_id, item_name, size_label, 'YARD'::text AS location, opening_stock FROM base_sizes
  UNION
  SELECT b.size_id, b.material_id, b.item_name, b.size_label, t.location, 0 AS opening_stock
  FROM base_sizes b
  JOIN txn_totals t ON t.material_id = b.material_id AND t.size_id = b.size_id
  WHERE t.location <> 'YARD'
)
SELECT 
  loc.size_id,
  loc.material_id,
  loc.item_name,
  loc.size_label,
  loc.location,
  (loc.opening_stock + COALESCE(t.txn_net, 0))::numeric(12, 4) AS net_stock_mt,
  5.0::numeric(12, 4) AS min_stock
FROM all_locations loc
LEFT JOIN txn_totals t ON t.material_id = loc.material_id AND t.size_id = loc.size_id AND t.location = loc.location
WHERE (loc.opening_stock + COALESCE(t.txn_net, 0)) <> 0;

-- 2. Today's Transactions Summary View (v_todays_summary)
DROP VIEW IF EXISTS public.v_todays_summary CASCADE;
CREATE OR REPLACE VIEW public.v_todays_summary 
WITH (security_invoker = true) AS
SELECT 
  COALESCE(UPPER(t.location), 'YARD') AS location,
  COALESCE(UPPER(t.txn_type), UPPER(t.type), 'IN') AS txn_type,
  COALESCE(m.item_name, 'General Material') AS item_name,
  COALESCE(s.size_label, 'General') AS size_label,
  SUM(COALESCE(t.qty_mt, 0))::numeric(12, 4) AS total_qty_mt,
  COUNT(t.id) AS tx_count
FROM public.transactions t
LEFT JOIN public.materials m ON m.id = t.material_id
LEFT JOIN public.item_sizes s ON s.id = t.size_id
WHERE COALESCE(t.is_reversed, false) = false
  AND DATE(t.created_at) = CURRENT_DATE
GROUP BY COALESCE(UPPER(t.location), 'YARD'), COALESCE(UPPER(t.txn_type), UPPER(t.type), 'IN'), m.item_name, s.size_label;

-- 3. Vendor Purchase Summary View (v_vendor_summary)
DROP VIEW IF EXISTS public.v_vendor_summary CASCADE;
CREATE OR REPLACE VIEW public.v_vendor_summary 
WITH (security_invoker = true) AS
SELECT 
  t.vendor_id,
  t.material_id,
  COALESCE(m.item_name, 'General Material') AS item_name,
  COALESCE(s.size_label, 'General') AS size_label,
  SUM(COALESCE(t.qty_mt, 0))::numeric(12, 4) AS total_qty_mt,
  AVG(COALESCE(t.rate, 0))::numeric(12, 2) AS avg_rate,
  MAX(t.created_at) AS last_purchase_date
FROM public.transactions t
LEFT JOIN public.materials m ON m.id = t.material_id
LEFT JOIN public.item_sizes s ON s.id = t.size_id
WHERE COALESCE(t.is_reversed, false) = false
  AND (UPPER(t.txn_type) = 'IN' OR UPPER(t.type) = 'IN')
GROUP BY t.vendor_id, t.material_id, m.item_name, s.size_label;

-- 4. Low Stock View (v_low_stock)
CREATE OR REPLACE VIEW public.v_low_stock 
WITH (security_invoker = true) AS
SELECT *
FROM public.v_current_stock
WHERE net_stock_mt <= min_stock;

-- 5. Non-Moving Stock View (v_non_moving_stock)
CREATE OR REPLACE VIEW public.v_non_moving_stock 
WITH (security_invoker = true) AS
SELECT *
FROM public.v_current_stock
WHERE net_stock_mt > 0;

-- 6. Grant Permissions Across Roles
GRANT SELECT ON public.v_current_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_todays_summary TO anon, authenticated, postgres;
GRANT SELECT ON public.v_vendor_summary TO anon, authenticated, postgres;
GRANT SELECT ON public.v_low_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_non_moving_stock TO anon, authenticated, postgres;

-- 7. Refresh PostgREST Schema Cache
NOTIFY pgrst, 'reload schema';

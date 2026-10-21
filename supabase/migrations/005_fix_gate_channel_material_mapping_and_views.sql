-- ============================================================================
-- MIGRATION: 005_fix_gate_channel_material_mapping_and_views.sql
-- DESCRIPTION: Sync material_id in transactions and update v_current_stock join
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

-- STEP 1: Synchronize transactions.material_id with item_sizes.material_id
UPDATE public.transactions t
SET material_id = s.material_id
FROM public.item_sizes s
WHERE t.size_id = s.id AND (t.material_id IS NULL OR t.material_id <> s.material_id);

-- STEP 2: Re-create Master Current Stock View (v_current_stock)
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
    COALESCE(s.current_stock_in, 0) AS initial_stock
  FROM public.item_sizes s
  LEFT JOIN public.materials m ON m.id = s.material_id
),
txn_totals AS (
  SELECT 
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
  GROUP BY t.size_id, COALESCE(UPPER(t.location), 'YARD')
),
yard_sizes AS (
  SELECT 
    b.size_id,
    b.material_id,
    b.item_name,
    b.size_label,
    'YARD'::text AS location,
    GREATEST(b.initial_stock, COALESCE(t_yard.txn_net, 0)) AS net_stock_mt
  FROM base_sizes b
  LEFT JOIN txn_totals t_yard ON t_yard.size_id = b.size_id AND t_yard.location = 'YARD'
),
factory_sizes AS (
  SELECT 
    b.size_id,
    b.material_id,
    b.item_name,
    b.size_label,
    'FACTORY'::text AS location,
    COALESCE(t_fac.txn_net, 0) AS net_stock_mt
  FROM base_sizes b
  JOIN txn_totals t_fac ON t_fac.size_id = b.size_id AND t_fac.location = 'FACTORY'
  WHERE COALESCE(t_fac.txn_net, 0) <> 0
),
combined_stock AS (
  SELECT * FROM yard_sizes
  UNION ALL
  SELECT * FROM factory_sizes
)
SELECT 
  c.size_id,
  c.material_id,
  c.item_name,
  c.size_label,
  c.location,
  c.net_stock_mt::numeric(12, 4),
  5.0::numeric(12, 4) AS min_stock
FROM combined_stock c
WHERE c.net_stock_mt <> 0;

-- STEP 3: Re-create Today's Summary View (v_todays_summary)
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
LEFT JOIN public.item_sizes s ON s.id = t.size_id
LEFT JOIN public.materials m ON m.id = COALESCE(s.material_id, t.material_id)
WHERE COALESCE(t.is_reversed, false) = false
  AND DATE(t.created_at) = CURRENT_DATE
GROUP BY COALESCE(UPPER(t.location), 'YARD'), COALESCE(UPPER(t.txn_type), UPPER(t.type), 'IN'), m.item_name, s.size_label;

-- STEP 4: Re-create Vendor Summary View (v_vendor_summary)
DROP VIEW IF EXISTS public.v_vendor_summary CASCADE;
CREATE OR REPLACE VIEW public.v_vendor_summary 
WITH (security_invoker = true) AS
SELECT 
  t.vendor_id,
  COALESCE(s.material_id, t.material_id) AS material_id,
  COALESCE(m.item_name, 'General Material') AS item_name,
  COALESCE(s.size_label, 'General') AS size_label,
  SUM(COALESCE(t.qty_mt, 0))::numeric(12, 4) AS total_qty_mt,
  AVG(COALESCE(t.rate, 0))::numeric(12, 2) AS avg_rate,
  MAX(t.created_at) AS last_purchase_date
FROM public.transactions t
LEFT JOIN public.item_sizes s ON s.id = t.size_id
LEFT JOIN public.materials m ON m.id = COALESCE(s.material_id, t.material_id)
WHERE COALESCE(t.is_reversed, false) = false
  AND (UPPER(t.txn_type) IN ('IN', 'OPENING', 'PURCHASE') OR UPPER(t.type) IN ('IN', 'OPENING', 'PURCHASE'))
GROUP BY t.vendor_id, COALESCE(s.material_id, t.material_id), m.item_name, s.size_label;

-- STEP 5: Re-create Low Stock & Non-Moving Stock Views
CREATE OR REPLACE VIEW public.v_low_stock 
WITH (security_invoker = true) AS
SELECT *
FROM public.v_current_stock
WHERE net_stock_mt <= min_stock;

CREATE OR REPLACE VIEW public.v_non_moving_stock 
WITH (security_invoker = true) AS
SELECT *
FROM public.v_current_stock
WHERE net_stock_mt > 0;

-- STEP 6: Grant Read Permissions to Roles
GRANT SELECT ON public.v_current_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_todays_summary TO anon, authenticated, postgres;
GRANT SELECT ON public.v_vendor_summary TO anon, authenticated, postgres;
GRANT SELECT ON public.v_low_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_non_moving_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.transactions TO anon, authenticated, postgres;

NOTIFY pgrst, 'reload schema';

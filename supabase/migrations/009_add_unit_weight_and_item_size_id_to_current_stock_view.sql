-- ============================================================================
-- MIGRATION: 009_add_unit_weight_and_item_size_id_to_current_stock_view.sql
-- DESCRIPTION: Master current stock views & movement reports with robust Factory/Yard location handling, transfer routing, and unit_weight_kg
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

-- STEP 1: Re-create Master Current Stock View (v_current_stock)
DROP VIEW IF EXISTS public.v_low_stock CASCADE;
DROP VIEW IF EXISTS public.v_non_moving_stock CASCADE;
DROP VIEW IF EXISTS public.v_current_stock CASCADE;

CREATE OR REPLACE VIEW public.v_current_stock 
WITH (security_invoker = true) AS
WITH base_sizes AS (
  SELECT 
    s.id AS size_id,
    s.id AS item_size_id,
    s.material_id,
    COALESCE(m.item_name, 'General Material') AS item_name,
    s.size_label,
    s.unit_weight_kg
  FROM public.item_sizes s
  LEFT JOIN public.materials m ON m.id = s.material_id
  WHERE m.item_name NOT IN ('Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB')
),
raw_movements AS (
  -- 1. Primary location impact (IN, OUT, ADJUSTMENT, RETURN, OPENING, and source of TRANSFER)
  SELECT 
    t.size_id,
    CASE 
      WHEN UPPER(TRIM(COALESCE(t.location, ''))) LIKE '%FACTORY%' 
        OR UPPER(TRIM(COALESCE(t.location, ''))) LIKE '%PLANT%' THEN 'FACTORY'
      ELSE 'YARD'
    END AS location,
    CASE 
      WHEN UPPER(COALESCE(t.txn_type, t.type, '')) IN ('IN', 'RETURN', 'ADJUSTMENT', 'OPENING') 
        THEN COALESCE(t.qty_mt, 0)
      WHEN UPPER(COALESCE(t.txn_type, t.type, '')) IN ('OUT', 'RESERVE', 'TRANSFER') 
        THEN -COALESCE(t.qty_mt, 0)
      ELSE 0
    END AS delta_mt
  FROM public.transactions t
  WHERE COALESCE(t.is_reversed, false) = false
    AND UPPER(COALESCE(t.txn_type, '')) <> 'PURCHASE'
    AND UPPER(COALESCE(t.type, ''))     <> 'PURCHASE'
    AND COALESCE(t.txn_id, '') NOT LIKE 'S-17%'
    AND COALESCE(t.txn_id, '') NOT LIKE 'IN_V_%'

  UNION ALL

  -- 2. Transfer destination location impact (+qty_mt to to_location)
  SELECT 
    t.size_id,
    CASE 
      WHEN UPPER(TRIM(COALESCE(t.to_location, ''))) LIKE '%FACTORY%' 
        OR UPPER(TRIM(COALESCE(t.to_location, ''))) LIKE '%PLANT%' THEN 'FACTORY'
      ELSE 'YARD'
    END AS location,
    COALESCE(t.qty_mt, 0) AS delta_mt
  FROM public.transactions t
  WHERE COALESCE(t.is_reversed, false) = false
    AND UPPER(COALESCE(t.txn_type, t.type, '')) = 'TRANSFER'
    AND COALESCE(t.to_location, '') <> ''
    AND UPPER(COALESCE(t.txn_type, '')) <> 'PURCHASE'
    AND UPPER(COALESCE(t.type, ''))     <> 'PURCHASE'
    AND COALESCE(t.txn_id, '') NOT LIKE 'S-17%'
    AND COALESCE(t.txn_id, '') NOT LIKE 'IN_V_%'
),
txn_totals AS (
  SELECT 
    r.size_id,
    r.location,
    SUM(r.delta_mt) AS txn_net
  FROM raw_movements r
  WHERE r.size_id IS NOT NULL
  GROUP BY r.size_id, r.location
)
SELECT 
  b.size_id,
  b.item_size_id,
  b.material_id,
  b.item_name,
  b.size_label,
  b.unit_weight_kg,
  t.location,
  t.txn_net::numeric(12, 4) AS net_stock_mt,
  5.0::numeric(12, 4) AS min_stock
FROM txn_totals t
JOIN base_sizes b ON b.size_id = t.size_id
WHERE t.txn_net <> 0;

-- STEP 2: Re-create Low Stock & Non-Moving Stock Views
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

-- STEP 3: Redefine get_stock_movement_report with transfer destination & location normalization
CREATE OR REPLACE FUNCTION public.get_stock_movement_report(
  start_date timestamp with time zone,
  end_date timestamp with time zone,
  loc_filter text DEFAULT 'ALL'::text
)
RETURNS TABLE(
  material_id bigint,
  item_name text,
  size_id bigint,
  size_label text,
  location text,
  opening_stock_mt numeric,
  period_in_mt numeric,
  period_out_mt numeric,
  closing_stock_mt numeric
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $function$
BEGIN
  RETURN QUERY
  WITH base_sizes AS (
    SELECT 
      s.id AS size_id,
      s.material_id,
      COALESCE(m.item_name, 'General Material') AS item_name,
      s.size_label
    FROM public.item_sizes s
    JOIN public.materials m ON m.id = s.material_id
    WHERE m.item_name NOT IN ('Binding Wire', 'Nails', 'Barbed Wire', 'Heavy Structure ISMB')
  ),
  raw_movements AS (
    -- Source / Primary movements
    SELECT
      t.size_id,
      t.created_at,
      t.type,
      t.txn_id,
      UPPER(COALESCE(t.txn_type, t.type, '')) AS txn_type,
      CASE 
        WHEN UPPER(TRIM(COALESCE(t.location, ''))) LIKE '%FACTORY%' 
          OR UPPER(TRIM(COALESCE(t.location, ''))) LIKE '%PLANT%' THEN 'FACTORY'
        ELSE 'YARD'
      END AS location,
      COALESCE(t.qty_mt, 0) AS qty_mt,
      false AS is_transfer_dest
    FROM public.transactions t
    WHERE COALESCE(t.is_reversed, false) = false
      AND UPPER(COALESCE(t.txn_type, '')) <> 'PURCHASE'
      AND UPPER(COALESCE(t.type, ''))     <> 'PURCHASE'
      AND COALESCE(t.txn_id, '') NOT LIKE 'S-17%'
      AND COALESCE(t.txn_id, '') NOT LIKE 'IN_V_%'

    UNION ALL

    -- Transfer destination movements (inward to to_location)
    SELECT
      t.size_id,
      t.created_at,
      t.type,
      t.txn_id,
      'TRANSFER_IN' AS txn_type,
      CASE 
        WHEN UPPER(TRIM(COALESCE(t.to_location, ''))) LIKE '%FACTORY%' 
          OR UPPER(TRIM(COALESCE(t.to_location, ''))) LIKE '%PLANT%' THEN 'FACTORY'
        ELSE 'YARD'
      END AS location,
      COALESCE(t.qty_mt, 0) AS qty_mt,
      true AS is_transfer_dest
    FROM public.transactions t
    WHERE COALESCE(t.is_reversed, false) = false
      AND UPPER(COALESCE(t.txn_type, t.type, '')) = 'TRANSFER'
      AND COALESCE(t.to_location, '') <> ''
      AND UPPER(COALESCE(t.txn_type, '')) <> 'PURCHASE'
      AND UPPER(COALESCE(t.type, ''))     <> 'PURCHASE'
      AND COALESCE(t.txn_id, '') NOT LIKE 'S-17%'
      AND COALESCE(t.txn_id, '') NOT LIKE 'IN_V_%'
  ),
  size_txns AS (
    SELECT
      t.size_id,
      t.location,

      -- Opening Stock: baseline opening OR movements before start_date
      ROUND(SUM(
        CASE
          WHEN (t.created_at < start_date OR t.type = 'OPENING' OR t.txn_id LIKE 'OPENING-%') 
               AND t.txn_type IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN','ADJUSTMENT','TRANSFER_IN')
            THEN t.qty_mt
          WHEN t.created_at < start_date 
               AND t.txn_type IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
            THEN -t.qty_mt
          ELSE 0
        END
      )::numeric, 3) AS opening_stock_mt,

      -- Period Inward: movements during period
      ROUND(SUM(
        CASE
          WHEN t.created_at BETWEEN start_date AND end_date 
               AND t.type <> 'OPENING' AND t.txn_id NOT LIKE 'OPENING-%'
               AND t.txn_type IN ('IN','INWARD','RETURN','ADJUSTMENT','TRANSFER_IN')
            THEN t.qty_mt
          ELSE 0
        END
      )::numeric, 3) AS period_in_mt,

      -- Period Outward: physical outward during the period
      ROUND(SUM(
        CASE
          WHEN t.created_at BETWEEN start_date AND end_date 
               AND t.txn_type IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
            THEN t.qty_mt
          ELSE 0
        END
      )::numeric, 3) AS period_out_mt,

      -- Closing Stock: net physical stock up to end_date
      ROUND(SUM(
        CASE
          WHEN (t.created_at <= end_date OR t.type = 'OPENING' OR t.txn_id LIKE 'OPENING-%')
               AND t.txn_type IN ('IN','INWARD','OPENING_STOCK','OPENING','RETURN','ADJUSTMENT','TRANSFER_IN')
            THEN t.qty_mt
          WHEN t.created_at <= end_date 
               AND t.txn_type IN ('OUT','OUTWARD','SALE','TRANSFER','RESERVE')
            THEN -t.qty_mt
          ELSE 0
        END
      )::numeric, 3) AS closing_stock_mt

    FROM raw_movements t
    WHERE (loc_filter = 'ALL' 
           OR t.location = CASE 
                             WHEN UPPER(TRIM(loc_filter)) LIKE '%FACTORY%' OR UPPER(TRIM(loc_filter)) LIKE '%PLANT%' THEN 'FACTORY' 
                             ELSE 'YARD' 
                           END)
    GROUP BY t.size_id, t.location
  )
  SELECT 
    b.material_id,
    b.item_name,
    b.size_id,
    b.size_label,
    COALESCE(st.location, CASE WHEN loc_filter = 'ALL' THEN 'YARD' ELSE (CASE WHEN UPPER(TRIM(loc_filter)) LIKE '%FACTORY%' OR UPPER(TRIM(loc_filter)) LIKE '%PLANT%' THEN 'FACTORY' ELSE 'YARD' END) END) AS location,
    COALESCE(st.opening_stock_mt, 0.000) AS opening_stock_mt,
    COALESCE(st.period_in_mt, 0.000) AS period_in_mt,
    COALESCE(st.period_out_mt, 0.000) AS period_out_mt,
    COALESCE(st.closing_stock_mt, 0.000) AS closing_stock_mt
  FROM base_sizes b
  LEFT JOIN size_txns st ON st.size_id = b.size_id
  WHERE (COALESCE(st.opening_stock_mt, 0) <> 0 
      OR COALESCE(st.period_in_mt, 0) <> 0 
      OR COALESCE(st.period_out_mt, 0) <> 0 
      OR COALESCE(st.closing_stock_mt, 0) <> 0);
END;
$function$;

-- STEP 4: Grant Permissions Across Roles
GRANT SELECT ON public.v_current_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_low_stock TO anon, authenticated, postgres;
GRANT SELECT ON public.v_non_moving_stock TO anon, authenticated, postgres;
GRANT EXECUTE ON FUNCTION public.get_stock_movement_report(timestamp with time zone, timestamp with time zone, text) TO anon, authenticated, postgres;

-- STEP 5: Reload Schema Cache
NOTIFY pgrst, 'reload schema';

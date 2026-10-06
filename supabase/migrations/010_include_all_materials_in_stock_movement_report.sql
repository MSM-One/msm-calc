-- ============================================================================
-- MIGRATION: 010_include_all_materials_in_stock_movement_report.sql
-- DESCRIPTION: Include all materials in get_stock_movement_report RPC to correctly support Factory materials (Binding Wire, Nails, etc.)
-- APP: MSM One (Metaroll Steel Mart Operating System)
-- ============================================================================

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

GRANT EXECUTE ON FUNCTION public.get_stock_movement_report(timestamp with time zone, timestamp with time zone, text) TO anon, authenticated, postgres;

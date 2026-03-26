-- Cardholder Feature Extraction for Churn Scoring
-- Straive Strategic Analytics | Issuer Practice
-- Parameters: :score_date

WITH base AS (
    SELECT
        a.account_id,
        a.account_open_date,
        a.credit_limit,
        a.autopay_flag,
        DATEDIFF('month', a.account_open_date, :score_date) AS account_tenure_months
    FROM dim_accounts a
    WHERE a.status = 'ACTIVE'
      AND a.product_type IN ('CREDIT', 'CHARGE')
),

spend_agg AS (
    SELECT
        t.account_id,
        SUM(CASE WHEN t.txn_date >= :score_date - 30  THEN t.amount ELSE 0 END) AS spend_30d,
        SUM(CASE WHEN t.txn_date >= :score_date - 90  THEN t.amount ELSE 0 END) AS spend_90d,
        SUM(CASE WHEN t.txn_date >= :score_date - 180 THEN t.amount ELSE 0 END) AS spend_180d,
        SUM(CASE WHEN t.txn_date >= :score_date - 365 THEN t.amount ELSE 0 END) AS spend_365d,
        COUNT(CASE WHEN t.txn_date >= :score_date - 30  THEN 1 END) AS txn_count_30d,
        COUNT(CASE WHEN t.txn_date >= :score_date - 90  THEN 1 END) AS txn_count_90d,
        AVG(CASE WHEN t.txn_date >= :score_date - 90  THEN t.amount END) AS avg_txn_value_90d,
        COUNT(DISTINCT CASE WHEN t.txn_date >= :score_date - 90 THEN t.merchant_id END) AS unique_merchants_90d,
        COUNT(DISTINCT CASE WHEN t.txn_date >= :score_date - 90 THEN t.mcc_category END) AS unique_categories_90d,
        MAX(t.txn_date) AS last_txn_date,
        MAX(CASE WHEN t.is_international = 1 THEN t.txn_date END) AS last_intl_txn_date,
        COUNT(CASE WHEN t.txn_type = 'CASH_ADVANCE' AND t.txn_date >= :score_date - 90 THEN 1 END) AS cash_advance_count_90d
    FROM fact_transactions t
    WHERE t.txn_date BETWEEN :score_date - 545 AND :score_date
      AND t.status = 'POSTED'
    GROUP BY t.account_id
),

revolve AS (
    SELECT
        b.account_id,
        AVG(CASE WHEN b.stmt_date >= :score_date - 90 THEN b.revolving_balance / NULLIF(b.credit_limit, 0) END) AS revolve_rate_90d
    FROM fact_billing_statements b
    GROUP BY b.account_id
),

rewards AS (
    SELECT
        r.account_id,
        COUNT(CASE WHEN r.redemption_date >= :score_date - 90 THEN 1 END) AS reward_redemption_count_90d
    FROM fact_reward_redemptions r
    GROUP BY r.account_id
),

credit_events AS (
    SELECT
        e.account_id,
        COUNT(CASE WHEN e.event_type = 'CREDIT_LIMIT_INCREASE'
                    AND e.event_date >= :score_date - 730 THEN 1 END) AS credit_limit_increase_count_24m
    FROM fact_account_events e
    GROUP BY e.account_id
)

SELECT
    b.account_id,
    b.account_tenure_months,
    b.autopay_flag                                              AS autopay_active,
    b.credit_limit,

    COALESCE(s.spend_30d, 0)                                   AS spend_30d,
    COALESCE(s.spend_90d, 0)                                   AS spend_90d,
    COALESCE(s.spend_180d, 0)                                  AS spend_180d,
    COALESCE(s.spend_365d, 0) - COALESCE(s.spend_180d, 0)     AS spend_yoy_delta,
    COALESCE(s.txn_count_30d, 0)                               AS txn_count_30d,
    COALESCE(s.txn_count_90d, 0)                               AS txn_count_90d,
    COALESCE(s.avg_txn_value_90d, 0)                           AS avg_txn_value_90d,
    COALESCE(s.unique_merchants_90d, 0)                        AS unique_merchants_90d,
    COALESCE(s.unique_categories_90d, 0)                       AS unique_categories_90d,
    DATEDIFF('day', s.last_txn_date, :score_date)              AS days_since_last_txn,
    DATEDIFF('day', s.last_intl_txn_date, :score_date)         AS days_since_last_international_txn,
    CASE WHEN DATEDIFF('day', s.last_txn_date, :score_date) > 60 THEN 1 ELSE 0 END AS dormancy_flag_60d,
    CASE WHEN DATEDIFF('day', s.last_txn_date, :score_date) > 90 THEN 1 ELSE 0 END AS dormancy_flag_90d,
    COALESCE(s.cash_advance_count_90d, 0)                      AS cash_advance_count_90d,
    COALESCE(r.revolve_rate_90d, 0)                            AS revolve_rate_90d,
    COALESCE(rw.reward_redemption_count_90d, 0)                AS reward_redemption_count_90d,
    COALESCE(s.spend_90d, 0) / NULLIF(b.credit_limit, 0)      AS credit_limit_utilisation,
    COALESCE(ce.credit_limit_increase_count_24m, 0)            AS credit_limit_increase_count_24m

FROM base b
LEFT JOIN spend_agg    s  ON b.account_id = s.account_id
LEFT JOIN revolve      r  ON b.account_id = r.account_id
LEFT JOIN rewards      rw ON b.account_id = rw.account_id
LEFT JOIN credit_events ce ON b.account_id = ce.account_id

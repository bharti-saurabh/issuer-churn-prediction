-- Churn Label Generation — 90-day Outcome Window
-- Straive Strategic Analytics | Issuer Practice
-- A cardholder is labelled churned if they close their account OR
-- become fully dormant (zero transactions) in the 90 days after score_date.

WITH closures AS (
    SELECT account_id, 1 AS churned_90d
    FROM fact_account_events
    WHERE event_type = 'ACCOUNT_CLOSURE'
      AND event_date BETWEEN :label_start AND :label_end
),

dormancy AS (
    SELECT a.account_id, 1 AS churned_90d
    FROM dim_accounts a
    WHERE NOT EXISTS (
        SELECT 1 FROM fact_transactions t
        WHERE t.account_id = a.account_id
          AND t.txn_date BETWEEN :label_start AND :label_end
          AND t.status = 'POSTED'
    )
    AND a.status = 'ACTIVE'
)

SELECT
    s.account_id,
    :label_start AS label_start,
    :label_end   AS label_end,
    CASE WHEN c.churned_90d = 1 OR d.churned_90d = 1 THEN 1 ELSE 0 END AS churned_90d
FROM stg_scoring_population s
LEFT JOIN closures c ON s.account_id = c.account_id
LEFT JOIN dormancy d ON s.account_id = d.account_id

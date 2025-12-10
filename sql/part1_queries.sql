/*
Task A: Monthly Financials
Dataset: bigquery-public-data.thelook_ecommerce
*/

WITH monthly_aggregates AS (
  SELECT
    DATE_TRUNC(DATE(b.created_at), MONTH) AS month
    ,SUM(a.sale_price) AS revenue
    ,COUNT(DISTINCT b.order_id) AS orders
    ,COUNT(DISTINCT a.id) AS units

  FROM `bigquery-public-data.thelook_ecommerce.order_items` a
  JOIN `bigquery-public-data.thelook_ecommerce.orders` b ON a.order_id = b.order_id
  
  WHERE a.status = 'Complete' 
    AND a.returned_at IS NULL
  
  GROUP BY 1
)

SELECT
  month
  ,revenue
  ,orders
  ,units

  ,ROUND(SAFE_DIVIDE(revenue, orders), 2) AS aov
  
  ,ROUND(
    SAFE_DIVIDE((revenue - LAG(revenue) OVER(ORDER BY month)), LAG(revenue) OVER(ORDER BY month)) * 100
  , 2) AS mom_revenue_growth_pct

FROM monthly_aggregates
ORDER BY 1 DESC;


------------------------------------------------------------------------------------------------------


/*
Task B: New vs Returning Mix
Dataset: bigquery-public-data.thelook_ecommerce
*/

WITH users_orders AS (
  SELECT
    a.user_id
    ,a.created_at AS order_date
    ,b.sale_price

  FROM `bigquery-public-data.thelook_ecommerce.order_items` b
  JOIN `bigquery-public-data.thelook_ecommerce.orders` a ON b.order_id = a.order_id
  WHERE b.status = 'Complete' 
    AND b.returned_at IS NULL
)

, user_activation AS (
  SELECT  
    user_id
    ,MIN(order_date) AS first_order_date
    ,DATE_TRUNC(DATE(MIN(order_date)), MONTH) AS first_order_month
  FROM users_orders 
  GROUP BY 1
)

, monthly_activity AS (
  SELECT 
    DATE_TRUNC(DATE(order_date), MONTH) AS month
    ,user_id
    ,SUM(sale_price) AS monthly_revenue
  FROM users_orders
  GROUP BY 1,2
)

, join_info AS (
  SELECT
    a.month
    ,a.user_id
    ,a.monthly_revenue
    ,b.first_order_month
    ,CASE 
      WHEN a.month = b.first_order_month THEN 'New'
      ELSE 'Returning'
    END AS customer_type

  FROM monthly_activity a 
    LEFT JOIN user_activation b ON a.user_id = b.user_id
)

SELECT
  month
  ,COUNT(DISTINCT user_id) AS active_customers
  ,COUNT(DISTINCT CASE WHEN customer_type = 'New' THEN user_id END) AS new_customers
  ,COUNT(DISTINCT CASE WHEN customer_type = 'Returning' THEN user_id END) AS returning_customers
  ,SUM(CASE WHEN customer_type = 'New' THEN monthly_revenue ELSE 0 END) AS revenue_new
  ,SUM(CASE WHEN customer_type = 'Returning' THEN monthly_revenue ELSE 0 END) AS revenue_returning
  
  ,ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN customer_type = 'Returning' THEN monthly_revenue ELSE 0 END),
      SUM(monthly_revenue)
    ) * 100, 
  2) AS pct_revenue_returning

FROM join_info
GROUP BY 1
ORDER BY 1 DESC;


------------------------------------------------------------------------------------------------------


/*
Task C: 90-Day Churn (Refactored with Base CTE)
Dataset: bigquery-public-data.thelook_ecommerce
*/

WITH base_completed_orders AS (
  SELECT
    a.user_id
    ,a.order_id
    ,a.created_at
    ,DATE_TRUNC(DATE(a.created_at), MONTH) AS order_month

  FROM `bigquery-public-data.thelook_ecommerce.order_items` b
  JOIN `bigquery-public-data.thelook_ecommerce.orders` a ON b.order_id = a.order_id
  
  WHERE b.status = 'Complete' 
    AND b.returned_at IS NULL
)

, monthly_active_users AS (
  SELECT DISTINCT
    order_month AS activity_month
    ,user_id
  FROM base_completed_orders
)

, churn_status AS (
  SELECT
    a.activity_month
    ,a.user_id
    ,COUNT(DISTINCT b.order_id) AS future_order_count
    
  FROM monthly_active_users a
  LEFT JOIN base_completed_orders b ON a.user_id = b.user_id

    AND b.created_at >= TIMESTAMP(DATE_ADD(a.activity_month, INTERVAL 1 MONTH))
    AND b.created_at < TIMESTAMP(DATE_ADD(a.activity_month, INTERVAL 4 MONTH))
  
  GROUP BY 1,2
)

SELECT
  activity_month
  ,COUNT(DISTINCT user_id) AS active_customers
  ,COUNT(DISTINCT CASE WHEN future_order_count = 0 THEN user_id END) AS churned_customers_3mo
  ,ROUND(
    SAFE_DIVIDE(
      COUNT(DISTINCT CASE WHEN future_order_count = 0 THEN user_id END),
      COUNT(DISTINCT user_id)
    ) * 100, 
  2) AS churn_rate_3mo

FROM churn_status
WHERE activity_month < DATE_SUB(CURRENT_DATE(), INTERVAL 4 MONTH)

GROUP BY 1
ORDER BY 1 DESC;


------------------------------------------------------------------------------------------------------


/*
Optional Stretch: Cohort Retention Heatmap
Dataset: bigquery-public-data.thelook_ecommerce
*/

WITH base_completed_orders AS (
  SELECT 
    b.user_id
    ,b.order_id
    ,DATE_TRUNC(DATE(b.created_at), MONTH) AS order_month

  FROM `bigquery-public-data.thelook_ecommerce.order_items` a
  JOIN `bigquery-public-data.thelook_ecommerce.orders` b ON a.order_id = b.order_id
  
  WHERE a.status = 'Complete' 
    AND a.returned_at IS NULL
)

, user_cohorts AS (
  SELECT
    user_id,
    MIN(order_month) AS cohort_month
  FROM base_completed_orders
  GROUP BY 1
)

, cohort_activity AS (
  SELECT DISTINCT
    b.cohort_month,
    a.user_id,
    DATE_DIFF(a.order_month, b.cohort_month, MONTH) AS month_number
  FROM base_completed_orders a
  JOIN user_cohorts b 
    ON a.user_id = b.user_id
)

, cohort_size AS (
  SELECT
    cohort_month,
    COUNT(DISTINCT user_id) AS total_users
  FROM user_cohorts
  GROUP BY 1
)

SELECT
  a.cohort_month,
  b.total_users AS cohort_start_size,
  a.month_number,
  
  COUNT(DISTINCT a.user_id) AS retained_users,
  
  ROUND(
    SAFE_DIVIDE(COUNT(DISTINCT a.user_id), b.total_users) * 100, 
  2) AS retention_rate_pct

FROM cohort_activity a
JOIN cohort_size b ON a.cohort_month = b.cohort_month
  
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 3 ASC;


------------------------------------------------------------------------------------------------------


/*
Task D: Dynamic Segment
How to use:
1. For Segments: Set key_segment_col to 'c.traffic_source', 'c.country', 'c.gender'.
2. For Global:   Set key_segment_col to "'Global'" (including the single quotes).
*/

DECLARE launch_date DATE DEFAULT '2022-01-15';
DECLARE window_days INT64 DEFAULT 56;

-- Change this to switch views:
-- Option A (Segmented): 'u.traffic_source'
-- Option B (Global):    "'Global'" 
DECLARE key_segment_col STRING DEFAULT "'Global'"; 

EXECUTE IMMEDIATE FORMAT("""
  WITH order_details AS (
    SELECT
      b.order_id,
      SUM(a.sale_price) AS order_total,

      %s AS key_segment, 
      
      CASE 
        WHEN DATE(b.created_at) BETWEEN DATE_SUB('%t', INTERVAL %d DAY) AND DATE_SUB('%t', INTERVAL 1 DAY) THEN '1_Pre_Launch'
        WHEN DATE(b.created_at) BETWEEN '%t' AND DATE_ADD('%t', INTERVAL %d DAY) THEN '2_Post_Launch'
        ELSE 'Out_of_Scope'
      END AS period,
      
      CASE 
        WHEN SUM(a.sale_price) >= 100 THEN 'Eligible (>$100)'
        ELSE 'Non-Eligible (<$100)'
      END AS order_segment

    FROM `bigquery-public-data.thelook_ecommerce.order_items` a
    JOIN `bigquery-public-data.thelook_ecommerce.orders` b ON a.order_id = b.order_id
    JOIN `bigquery-public-data.thelook_ecommerce.users` c ON b.user_id = c.id
    
    WHERE a.status = 'Complete' 
      AND a.returned_at IS NULL
    
    GROUP BY 1, 3, b.created_at
  )

  SELECT
    period,
    key_segment,
    order_segment,
    
    COUNT(DISTINCT order_id) AS total_orders,
    SUM(order_total) AS total_revenue,
    ROUND(AVG(order_total), 2) AS aov,
    
    ROUND(
      COUNT(DISTINCT order_id) / 
      SUM(COUNT(DISTINCT order_id)) OVER(PARTITION BY period, key_segment), 
    4) * 100 AS pct_share_within_segment

  FROM order_details
  WHERE period != 'Out_of_Scope'
  GROUP BY 1, 2, 3
  --ORDER BY 2, 1, 3
""", 
  key_segment_col,  
  launch_date, window_days, launch_date, 
  launch_date, launch_date, window_days
);

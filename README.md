# PEEK

### Task A: Monthly Financials

**Overview**
This task aggregates financial metrics from the `thelook_ecommerce` dataset to track monthly performance.

**Dataset Sources**
* `bigquery-public-data.thelook_ecommerce.order_items`
* `bigquery-public-data.thelook_ecommerce.orders`

**Assumptions & Logic**
* **Timeframe:** All time (aggregated by month).
* **Revenue:** Calculated as the sum of `sale_price`.
* **Metric Logic:**
    * **Orders:** Count of distinct `order_id`.
    * **Units:** Count of distinct line item IDs (`id`).
    * **AOV:** Revenue / Total Orders.
    * **MoM Growth:** Calculated using previous month's revenue (Lag Window Function).

> **Crucial Definition:** A "Completed sale" is strictly filtered where:
> `status = 'Complete'` **AND** `returned_at IS NULL`

------------------------------

### Task B: New vs. Returning Mix

**Overview**
This task analyzes customer retention by distinguishing between acquisition (New) and retention (Returning) behavior. It calculates the revenue mix and customer counts for every month.

**Dataset Sources**
* `bigquery-public-data.thelook_ecommerce.order_items`
* `bigquery-public-data.thelook_ecommerce.orders`

**Assumptions & Logic**
1.  **Identify Activation Date:** Calculate the `MIN(created_at)` for every user to find their specific "First Order Month."
2.  **Tag Monthly Activity:** Join the sales data with the user's activation date and apply the following logic:
    * **New Customer:** `Current_Month` == `Activation_Month`
    * **Returning Customer:** `Current_Month` > `Activation_Month`
3.  **Aggregate:** Group by month to sum revenue and count distinct users based on these tags.

**Key Definitions**
* **Active Customer:** Any user with a "Completed" order in the reporting month.
* **New:** A customer whose first-ever completed order occurred in the current reporting month.
* **Returning:** A customer active in the current month who had their first completed order in a *previous* month.

-------------------------------

### Task C: 90-Day Churn (Calendar Window Method)

**Overview**
This task calculates churn rates by observing customer behavior over a specific 3-month calendar window (e.g., Feb–Mar–Apr) rather than a fixed 90-day count. This ensures alignment with calendar boundaries regardless of month length (28, 30, or 31 days).

**Dataset Sources**
* `bigquery-public-data.thelook_ecommerce.order_items`
* `bigquery-public-data.thelook_ecommerce.orders`

**Assumptions & Logic**
1.  **Define Cohort (Month M):** Identify every user who was "Active" in a specific month.
2.  **Define Window (Next 3 Months):** For these users, check for *any* completed purchase in the subsequent 3 full calendar months.
    * *Start:* 1st of the next month (`INTERVAL 1 MONTH`)
    * *End:* 1st of the month 4 months out (`INTERVAL 4 MONTH`, exclusive)
3.  **Strict Retention Check:** A user is only "Retained" if their future order is **Completed** and not returned.

**Classifications**
* **Retained:** User placed $\ge$ 1 completed order in the 3-month window.
* **Churned:** User placed 0 completed orders in the 3-month window.

> **Technical Constraint:**
> To avoid misleading "100% churn" stats, we must exclude recent months where the 3-month window hasn't fully elapsed.
>
> *Filter Applied:* `activity_month < DATE_SUB(CURRENT_DATE(), INTERVAL 4 MONTH)`

-------------------------------

### Optional Stretch: Cohort Retention Heatmap

**Overview**
This task moves beyond aggregate churn rates to build a **Cohort-Based Retention Heatmap**. This visualization tracks specific groups of users (Cohorts) over time to see how quickly retention degrades for each acquisition month.

**Dataset Sources**
* `bigquery-public-data.thelook_ecommerce.orders`

**Assumptions & Logic**
1.  **Define Cohort (Rows):** Determine the **First Purchase Month** for every user.
2.  **Calculate Lifecycle Stage (Columns):** For every subsequent purchase, calculate the "Month Index" (time elapsed since joining).
    * *Formula:* `DATE_DIFF(Purchase_Month, Cohort_Month, MONTH)`
    * *Month 0:* The acquisition month (typically 100% retention).
    * *Month 1:* The first full month after joining.
3.  **Aggregate & Rate:** Count distinct users for every `(Cohort, Month_Index)` pair and divide by the original cohort size.

**Visualization Structure**
* **Rows:** Cohort Month (e.g., Jan 2022, Feb 2022).
* **Columns:** Months Since First Purchase (0, 1, 2, ... 12+).
* **Values:** Retention Rate % (visualized by color intensity).

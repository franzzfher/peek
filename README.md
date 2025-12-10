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

-------------------------------

### Task D: Product Change Impact (Scenario Analysis)

**Scenario Overview**
This task simulates an impact analysis for a hypothetical product feature launched on **2022-01-15**:
* **Feature:** A checkout header promoting "Free shipping for orders over $100."
* **Goal:** Evaluate the impact on Average Order Value and Revenue.

**Methodology: Pre/Post Analysis**
A/B testing data is not available in the public dataset then we use a **Pre/Post approach**:
1.  **Define Windows:** Compare the 8 weeks *before* the launch to the 8 weeks *after*.
    * *Pre-Launch:* `2021-11-20` to `2022-01-14`
    * *Post-Launch:* `2022-01-15` to `2022-03-12`
2.  **Define Proxy Segments:** We segment orders based on the value to see if users "pushed" their baskets to meet the threshold.
    * *Eligible:* Order Total $\ge$ $100
    * *Non-Eligible:* Order Total < $100
3.  **Key Segments:** The query breaks down impact by `Traffic Source`, `Country`, or `Gender` to uncover hidden wins (e.g., did Email traffic respond better than Organic?).

**Assumptions & Logic**
* **Seasonality:** We assume the "Pre" period (Nov-Jan) and "Post" period (Jan-Mar) are roughly comparable, though holiday seasonality (Q4) likely skews the Pre-period baseline.
* **Attribution:** We assume all users saw the banner, as we lack experimental assignment data.

**Technical Solution: Dynamic SQL**
To avoid generating lots of rows of messy data when grouping by every dimension at once, this query uses `EXECUTE IMMEDIATE`, which allows the analyst to **dynamically switch** between a "Global View" and a specific "Segment View" (e.g., by Traffic Source) without rewriting the code.

**Missing Data**
To perform a better impact analysis in a real-world scenario, the following sources would be required to prove causality and calculate ROI.

#### 1. Experimentation (To Prove Causality)
Relying on Pre/Post analysis allows seasonality or external marketing to skew results. To isolate the impact of the banner, we need:
* **Experiment assignment:** A log mapping each `user_id` to a `test_group`.
* **Exposure timestamp:** The exact moment a user saw the banner. We could filter for orders placed after this timestamp to measure a possible true change.

#### 2. Financial (To Measure ROI)
The current dataset calculates Revenue and Gross Profit, but it misses the primary cost driver of this specific promotion: shipping fees.
* **Shipping cost:** The amount the company pays the carrier to ship the package.
* **Shipping revenue:** The amount the customer paid for shipping.

> **Why it matters:** If Average Order Value increases by $5, but the company pays $8 to ship, the promotion actually *loses* money.

#### 3. Behavioral Funnel
We would need cart event data to see if a user is actively "building" their carts to reach the threshold.
* **Cart event logs:** Timestamps of `add_to_cart` actions.
* **Cart value at checkout:** A snapshot of the total cart value immediately before the purchase was finalized.

> **Why it matters:** This helps identify **"Cart stuffing"**—users adding low-value (possibly filler) items just to cross the $100 threshold. This behavior differs significantly from upselling affecting long-term value.

#### 4. Qualitative & Operational Data
* **User sentiment:** Survey data to understand if a customer perceived the $100 threshold as valuable or too high.
* **Return reasons:** Data distinguishing between "Did not fit" vs. "Ordered to get the promo." High return rates from some users can destroy the profitability of free shipping promos.



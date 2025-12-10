# PEEK

## Part 1: SQL

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

-------------------------------

## Part 2A: Visualization

* [View "New vs Returning" Report on Looker Studio](https://lookerstudio.google.com/reporting/3502b190-8019-4d52-aa49-0b668dcc1458/page/TlJ0C)

* [View "Churn vs Revenue" Report on Looker Studio](https://lookerstudio.google.com/reporting/6285b635-6eba-4728-85af-9a0e3a1df580/page/TlJ0C)

* [View "Cohort Retention Heatmap" Report on Looker Studio](https://lookerstudio.google.com/reporting/d60b7725-20a7-4744-9315-07960bcfdb1e/page/TlJ0C)

* [View "Dynamic Segment" Report on Looker Studio](https://lookerstudio.google.com/reporting/d471800c-27fc-414d-829b-cb28f55f8751/page/TlJ0C)

-------------------------------

## Part 2B: Strategic Insights & Recommendations

### 1. Definitions & Alternatives
*How we defined key metrics vs. how we might define them differently in other contexts.*

* **Active Customer:** Defined as a user who placed **at least one completed order** (`status='Complete'` and `returned_at IS NULL`) within the reporting period.
    * *Alternative Definition:* In a non-transactional app or environment, we could define Active based on **engagement** (e.g., "Logged in within last 30 days") rather than just purchases. This captures users who are evaluating the product but have not converted yet.
 
* **Churned Customer:** Defined using a **3-Month Calendar Window** (Task C). A user active in Month $M$ is "churned" if they place **zero** orders in months $M+1, M+2, \text{and } M+3$.
    * *Alternative Definition:* A **Rolling 90-Day Window** (e.g., churned if `days_since_last_order > 90`). This is more precise for triggering automated win-back emails but is harder to check on a monthly chart.

* **New vs. Returning:**
    * **New:** First purchase in the current month.
    * **Returning:** Active in current month, but first purchase was in a prior month.
    * *Alternative Definition:* We could add a **"Resurrected"** metric. Users who were inactive for >6 months and then returned. Treating them simply as "Returning" masks the effectiveness of specific campaigns.

### 2. Most Important Trend for Leadership

**The "Cohort Retention Heatmap" (See Task C - Stretch)**

* **The Trend:** While aggregate monthly revenue might look flat or growing, the **cohort heatmap** reveals if newer groups of customers are churning *faster* than older groups.
* **Why it matters:** If January 2022 cohort retains at 20% but January 2023 cohort retains at only 10%, we are "burning" through our total addressable market.
* **Impact:** This could indicate that despite higher acquisition numbers, the retention is getting worse—likely due to declining quality or maybe poor customer fit from lower quality traffic sources.

### 3. Product Experiment Proposal

**The Experiment:** Dynamic Free Shipping Threshold (Building on Task D)
* **Hypothesis:** The hypothetical $100 threshold analyzed in Task D might be too high for mid-tier users, causing cart abandonment.
* **Target Segment:** Users with a "Cart Value" between **$60 and $90** (High intent, but below the current $100 gap).
* **The Test:**
    * **Control Group:** Free shipping at $100.
    * **Variant Group:** Free shipping at $75.
* **Success Metrics:**
    * *Primary:* **Net Margin Impact** (Did the increase in conversion volume outweigh the incremental shipping cost?).
    * *Secondary:* Cart Abandonment Rate for the $60–$90 segment.

### 4. Product Health Dashboard
*The 5–7 metrics I would group into a dashboard to monitor product health (AARRR).*

| Category | Metric | Why It Matters |
| :--- | :--- | :--- |
| **Acquisition** | **Traffic Source Mix** | Are we relying too heavily on one channel (e.g., Organic Search vs. Paid)? |
| **Activation** | **New User AOV** | Are we acquiring "high value" users, or just cheap traffic? |
| **Retention** | **Cohort Retention Rate (Month 3)** | Are users sticking around after the initial hype? |
| **Revenue** | **Net Margin** | Measures profitability after deducting the direct costs of goods and shipping. (Revenue - COGS - Shipping) / Revenue. |
| **Revenue** | **Repurchase Rate** | Perc of this month's buyers who are Returning (Target: >30% for healthy e-com). |
| **Health** | **Return Rate %** | A spike here indicates product quality issues or "bracketing" (buying multiple sizes to return). |

-------------------------------

## Part 3: AI & Analytics

### How I used AI in this challenge
I utilized AI tools (LLMs) primarily as a **Thought Partner** and **Syntax Accelerator** rather than a "Solution Generator."
* **Strategy Refinement:** I used AI to brainstorm potential edge cases in my churn logic (e.g., "How do we handle the most recent months where the 90-day window hasn't closed yet?").
* **Documentation Formatting:** I used AI to convert raw SQL comments into professional, readable Markdown tables and "Technical Spec" sections for the README.
* **Dynamic SQL Construction:** I used AI to help structure the complex `EXECUTE IMMEDIATE` syntax for the dynamic segment analysis in Task D, which is error-prone to write from scratch.

### Example Prompt & Validation
**The Prompt Used:**
> "Write a BigQuery SQL query to calculate a 90-day churn rate. The logic should be: User is active in Month M, and Churned if they have 0 completed orders in the window [M+1, M+3].
>
> **Constraint:** Ensure the query handles the 'future gap'—do not calculate churn for recent months where the full 90-day window has not yet elapsed."

**How I Validated the Output:**
I did not blindly run everything. I performed the following validation checks:
1.  **Logic "Smell Test":** I checked the `WHERE` clause to ensure it included the specific logic `activity_month < DATE_SUB(CURRENT_DATE(), INTERVAL 4 MONTH)`. Without this manual check, the AI might have returned a query showing "100% churn" for the current month, which is technically correct code but **analytically false**.
2.  **Definition Verification:** I verified that the AI used my strict definition of "Active" (`status='Complete'`) in the `JOIN` conditions, rather than just counting *any* row in the `orders` table (which would incorrectly include returns or cancelled orders).
3.  **Syntax check:** I reviewed the `DATE_TRUNC` and `INTERVAL` functions to ensure they matched BigQuery's specific dialect, as LLMs sometimes default to PostgreSQL syntax.

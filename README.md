# peek

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
    * **Units:** Count of distinct line item IDs (`oi.id`).
    * **AOV:** Revenue / Total Orders.
    * **MoM Growth:** Calculated using previous month's revenue (Lag Window Function).

> **Crucial Definition:** A "Completed sale" is strictly filtered where:
> `status = 'Complete'` **AND** `returned_at IS NULL`

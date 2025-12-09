# peek

### Task 1

**Table Overviews**
* `order_items`: Contains revenue and status data.
* `users`: Contains demographic data.

> **Crucial Definition:** A "Completed sale" is strictly defined as:
> `order_items.status = 'Complete'` AND `returned_at IS NULL`

**Key Metrics**
* **Revenue:** Calculated as `SUM(sale_price)`.
* **Cost of Goods Sold (COGS):** Derived from `inventory_items.cost`.

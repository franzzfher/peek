# peek

Table definitions:
Understand that order_items contains revenue and status, while users contains demographics.
Crucial Definition: Note that a "Completed sale" is defined strictly as order_items.status='Complete' AND returned_at IS NULL.
Revenue Definition: Revenue is SUM(sale_price); Cost of Goods Sold (COGS) comes from inventory_items.cost.

# Decisions log

Every assumption or cleaning decision is appended here (newest at the bottom).

| Date | Phase | Decision | Reason | Impact |
|------|-------|----------|--------|--------|
| 2026-11-20 | 1 | Use `customer_unique_id` as the customer key. | `customer_id` is generated per order, so the same person appears under several `customer_id`s. | All customer-level metrics and joins go through the `customers` table to map `customer_id` → `customer_unique_id`; counting `customer_id` would overstate customers and understate repeat buying. |

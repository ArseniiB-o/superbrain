# Team Memory: data
Last updated: 2026-03-26

## Accumulated Knowledge
- Always add indexes on foreign keys and frequently queried columns
- Use EXPLAIN ANALYZE before finalizing any complex query
- Soft deletes: use deleted_at timestamp, not hard deletes
- Migrations: always reversible (up + down)
- Timestamps: always UTC, store as timestamptz in PostgreSQL

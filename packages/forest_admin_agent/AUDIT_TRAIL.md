# Audit trail

Capture who changed what (before/after) for every change Forest performs through its data layer, and
persist it into a SQL database. Built into the agent: it turns on as soon as an audit-trail **database
is configured**, and stays completely off otherwise.

Two parts, both internal:

- **Capture** (`ForestAdminAgent::AuditTrail::Capture`) — datasource-agnostic. It instruments every
  collection through the customizer hooks, so it behaves the same whether the audited datasource is
  ActiveRecord, Mongoid, etc.
- **Storage** (`ForestAdminAgent::AuditTrail::Store`) — ActiveRecord-backed. It creates the `forest`
  schema and creates/evolves the `audit_logs` table through versioned migrations, and reads the
  per-record history back for the routes below.

Storage uses ActiveRecord: outside Rails, add `gem 'activerecord'` (and the adapter gem) to your
Gemfile. Nothing is loaded and no connection is opened until the feature is configured.

## Turn it on

### Rails (forest_admin_rails)

```ruby
# config/initializers/forest_admin_rails.rb
ForestAdminRails.configure do |config|
  config.auth_secret = ENV['FOREST_AUTH_SECRET']
  config.env_secret  = ENV['FOREST_ENV_SECRET']

  config.audit_trail = {
    database: { # or an ActiveRecord URL: ENV['AUDIT_TRAIL_DATABASE_URL']
      adapter: 'postgresql', host: ENV['AUDIT_DB_HOST'], port: ENV['AUDIT_DB_PORT'],
      username: ENV['AUDIT_DB_USER'], password: ENV['AUDIT_DB_PASSWORD'], database: ENV['AUDIT_DB_NAME']
    }
  }
end
```

### Plain agent (no Rails)

```ruby
ForestAdminAgent::Builder::AgentFactory.instance.setup(
  auth_secret: ENV['FOREST_AUTH_SECRET'],
  env_secret: ENV['FOREST_ENV_SECRET'],
  # ...usual options...
  audit_trail: { database: ENV['AUDIT_TRAIL_DATABASE_URL'] }
)
```

| option       | description                                                                          |
| ------------ | ------------------------------------------------------------------------------------ |
| `database`   | ActiveRecord URL or config hash. **Setting it activates the audit trail.**           |
| `schema`     | Postgres schema holding the table (default `forest`; ignored on other adapters)      |
| `table_name` | default `audit_logs`                                                                 |
| `redact`     | `{ 'collection_name' => ['field', ...] }` — values masked while recording the change |

On the first write or read the store ensures the schema exists and runs any pending migrations; every
create / update / delete performed through Forest then writes one row per record, and the **Historic**
tab in the UI reads from the same table.

## Routes

All routes live under `/forest/_audit-trail`, are registered only when `audit_trail[:database]` is
set, and require read permission on the target collection (`can?(:read, collection)`).

### Record-history route

`GET /forest/_audit-trail/{collection}/{recordId}` returns the current page of history (newest first
by default) together with the filtered total:

```json
{ "data": [ /* current page rows */ ], "meta": { "count": 137 } }
```

`meta.count` is the number of rows matching the active filters (not the absolute total) and is
independent of the page. Optional filters (all combine with `AND`; omit them for the full history):

| query param | format                           | effect                                          |
| ----------- | -------------------------------- | ----------------------------------------------- |
| `userIds`   | comma-separated integers `12,45` | keep only entries whose `user_id` is in the list |
| `startDate` | `YYYY-MM-DD` or datetime (incl.) | keep entries from this lower bound onward       |
| `endDate`   | `YYYY-MM-DD` or datetime (incl.) | keep entries up to this upper bound             |

`startDate` / `endDate` are read as **local wall-clock time** in the request `timezone` query param
(e.g. `Europe/Paris`, default `UTC`) and converted to a UTC instant before querying, so filtering
happens in SQL. Two shapes are accepted:

- **Bare day** `YYYY-MM-DD` — `startDate` snaps to `00:00:00.000`, `endDate` to `23:59:59.999`.
- **Datetime** `YYYY-MM-DD[T| ]HH:mm[:ss]` — `T` or space separator, seconds optional; when seconds
  are omitted `endDate` is completed to `:59.999` and `startDate` stays at `:00.000`.

Both bounds are **inclusive**. Defensive parsing: non-numeric `userIds` tokens are dropped
(`12,abc,45` → `12,45`), and a `startDate` / `endDate` matching no accepted format returns **HTTP
400** (`ValidationError`); an invalid `timezone` likewise returns **400**.

Pagination follows JSON:API: `page[number]` is 1-based (default `1`), `page[size]` defaults to `20`
and is capped at `100`; out-of-bound or non-numeric values fall back to the defaults rather than
erroring. Sorting follows JSON:API `sort` on `timestamp`: `sort=-timestamp` (or absent/unrecognized)
is newest first, `sort=timestamp` is oldest first. Ties on equal timestamps fall back to insertion
order (the auto-increment `id`), so paging is deterministic in either direction.

All three routes serialize audit records the same way: top-level keys are camelCased
(`recordId`, `userId`, `correlationKey`, `previousValues`, `new_values` → `newValues`), while the
`previousValues` / `newValues` hashes keep the audited record's own column names.

A record that no longer exists keeps its history: only a record that still exists *outside* the
caller's permission scope is refused (404). Inspecting what was deleted is much of the point of an
audit trail, and the delete event itself is the last thing recorded.

### Correlation route

`GET /forest/_audit-trail/correlation/{correlationKey}` returns `{ "data": [...] }` — the
operation(s) recorded under one `correlation_key` for a single record (usually one), oldest first, or
an empty array if none. Scoped through query params; same auth and gating as above.

| query param  | required | effect                                                       |
| ------------ | -------- | ------------------------------------------------------------ |
| `collection` | yes      | collection the record belongs to (also the permission scope) |
| `recordId`   | yes      | packed record id to scope the lookup                         |

A missing `collection` or `recordId` returns **HTTP 400** (`ValidationError`).

### Batch correlation route

`GET /forest/_audit-trail/correlations` returns `{ "data": [...] }` — a **flat** list of every record
whose `correlation_key` is in `correlationKeys`, scoped to one record (the client groups by
`correlation_key`). Same auth and gating; empty array when nothing matches.

| query param       | required | effect                                                       |
| ----------------- | -------- | ------------------------------------------------------------ |
| `correlationKeys` | yes\*    | comma-separated keys; blank tokens are dropped               |
| `collection`      | yes      | collection the record belongs to (also the permission scope) |
| `recordId`        | yes      | packed record id to scope the lookup                         |

\* To dodge any URL length limit, the same path also accepts **`POST`** with a JSON body
`{ "correlationKeys": [...], "collection": "...", "recordId": "..." }` (the body array takes
precedence over the query param). An empty/absent key list returns `{ "data": [] }` without hitting
the store. A missing `collection` or `recordId` returns **HTTP 400** (`ValidationError`).

## Smart actions

Running a smart action writes one row per selected record, in the same table:

| column      | value                                                                      |
| ----------- | -------------------------------------------------------------------------- |
| `operation` | `action` when it ran, `action_failed` when it raised                       |
| `newValues` | the submitted form values (redacted with the same `redact` config)          |
| `recordId`  | each selected record — empty for a global action or a select-all selection  |

**Which** action ran is not stored: the Forest activity logs already record it, and
`correlationKey` is the join between the two.

A **global** action targets no record, and a **select-all** selection only tells the agent which ids were
*excluded*, so naming the targets would mean querying the whole selection: those runs are recorded once,
attached to no record. Recording is best-effort — a failing audit database logs an error rather than
breaking the action.

> **What an action changes is only audited when it goes through Forest.** `context.collection.update(...)`
> passes through the same hooks as any other write, so it produces the usual field-level rows sharing the
> action's `correlationKey`. A direct ORM write (`Customer.find(id).update!(...)`) is invisible to the
> agent, so nothing is recorded for it beyond the invocation row above.

## What gets stored

`forest.audit_logs`, one row per audited change:

| column            | description                                                 |
| ----------------- | ----------------------------------------------------------- |
| `id`              | auto-increment primary key                                  |
| `timestamp`       | when the change happened                                    |
| `operation`       | `create` / `update` / `delete`                              |
| `collection`      | audited collection name                                     |
| `record_id`       | packed record id (primary keys joined by `\|`)              |
| `user_id`         | the Forest user who made the change                         |
| `correlation_key` | per-request id; groups every change made within one request |
| `previous_values` | values before the change (JSON)                             |
| `new_values`      | values after the change (JSON)                              |

`previous_values` / `new_values` store **only the parts that actually changed**: nested hashes and
arrays of hashes are diffed structurally, so a single sub-field change records just that leaf. Only
writable columns are audited — read-only, computed and DB-managed fields are never written by Forest.

The `correlation_key` is the agent's per-request id (`caller.request_id`), generated by the agent and
echoed back to the client in the `X-Forest-Correlation-Id` response header — so every change made in
one request shares a key, and the caller can tie it to its own activity log.

## Concurrent writes to one record

The before/after values are captured around the write, not inside it: the customizer hooks bracket the
write as separate calls, and the data layer deliberately exposes no lock or transaction primitive since
it spans ActiveRecord, Mongoid, HTTP APIs and more.

So when two writes race on the same record, both snapshot the same state and the one that lands second
records a `previousValues` that had already been overwritten. `newValues` is always exact — it is the
patch that was written — and no row is ever lost; only the prior state of an overlapping write can be
stale. Exact before-images under concurrency need the database itself (triggers, or CDC), not an agent
hook.

## Schema migrations & concurrency

The table is created/evolved through an ordered, append-only migration list tracked in a dedicated
`forest.audit_migrations` table. On Postgres the migrations run inside a transaction-scoped advisory
lock so several agents booting at once apply them one after another; the schema is created (and
committed, idempotently) first since the lock can't cover a not-yet-existing schema.

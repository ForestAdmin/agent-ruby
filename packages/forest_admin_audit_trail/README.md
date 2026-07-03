# forest_admin_audit_trail

Capture who changed what (before/after) for every change Forest performs through its data layer, and
persist it into a SQL database. Ruby port of the Node `@forestadmin/plugin-audit-trail`.

Two decoupled parts:

- **Capture** — datasource-agnostic. It instruments every collection through the Forest customizer
  hooks, so it works the same whether the audited datasource is ActiveRecord, Mongoid, etc.
- **Storage** — where the records are written. Ships a **SQL store** (ActiveRecord) that creates the
  `forest` schema and creates/evolves the `audit_logs` table through versioned migrations, plus an
  in-memory store for tests.

## Use it in an agent

`ForestAdminAuditTrail::Stores::SqlStore` both **writes** every audited change and **reads** the
per-record history back. The integration has two halves that must share the **same** store instance:

- the agent `audit_trail` option — so the record-history routes are mounted and read from the table;
- `agent.use(ForestAdminAuditTrail::Plugin, store:)` — so every change is captured into that table.

Add the gem:

```ruby
# Gemfile
gem 'forest_admin_audit_trail'
```

### Rails (forest_admin_rails)

Build the store once in an initializer and hand it to the agent through `config.audit_trail`. A
constant keeps the single instance reachable from the agent factory:

```ruby
# config/initializers/forest_admin_rails.rb
AUDIT_TRAIL_STORE = ForestAdminAuditTrail::Stores::SqlStore.new(
  connection_string: { # or any ActiveRecord config / URL
    adapter: 'postgresql', host: ENV['AUDIT_DB_HOST'], port: ENV['AUDIT_DB_PORT'],
    username: ENV['AUDIT_DB_USER'], password: ENV['AUDIT_DB_PASSWORD'], database: ENV['AUDIT_DB_NAME']
  }
)

ForestAdminRails.configure do |config|
  config.auth_secret = ENV['FOREST_AUTH_SECRET']
  config.env_secret  = ENV['FOREST_ENV_SECRET']
  # exposes GET /forest/_audit-trail/{collection}/:id and the correlation routes below
  config.audit_trail = { store: AUDIT_TRAIL_STORE }
end
```

Then install the capture plugin where you build the agent (`lib/forest_admin_rails/create_agent.rb`),
reading the **same** store back from the config so writes and reads agree:

```ruby
# lib/forest_admin_rails/create_agent.rb
@agent = ForestAdminAgent::Builder::AgentFactory.instance
                                                .add_datasource(my_datasource)

@agent.use(ForestAdminAuditTrail::Plugin, store: ForestAdminRails.config.audit_trail[:store])

@agent.build
```

### Plain agent (no Rails)

```ruby
store = ForestAdminAuditTrail::Stores::SqlStore.new(connection_string: ENV['AUDIT_TRAIL_DATABASE_URL'])

ForestAdminAgent::Builder::AgentFactory.instance.setup(
  auth_secret: ENV['FOREST_AUTH_SECRET'],
  env_secret: ENV['FOREST_ENV_SECRET'],
  # ...usual options...
  audit_trail: { store: store }
)

agent.use(ForestAdminAuditTrail::Plugin, store: store)
```

On the first write or read the store ensures the `forest` schema exists and runs any pending
migrations to create/upgrade `forest.audit_logs`; every create / update / delete performed through
Forest then writes one row per record, and the **Historic** tab in the UI reads from the same table.

> The record-history routes are mounted **only** when `audit_trail[:store]` is set. Leave it unset
> (the default) and the feature stays off — the plugin can still write to a `LogStore` if used alone.

## Routes

All routes live under `/forest/_audit-trail`, are gated on `audit_trail[:store]` being configured,
and require read permission on the target collection (`can?(:read, collection)`).

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
order (the SQL store's auto-increment `id`), so paging is deterministic in either direction.

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

## What gets stored

`forest.audit_logs`, one row per audited change:

| column            | description                                          |
| ----------------- | ---------------------------------------------------- |
| `id`              | auto-increment primary key                           |
| `timestamp`       | when the change happened                             |
| `operation`       | `create` / `update` / `delete`                       |
| `collection`      | audited collection name                              |
| `record_id`       | packed record id (primary keys joined by `\|`)       |
| `user_id`         | the Forest user who made the change                  |
| `correlation_key` | per-request id; groups every change made within one request    |
| `previous_values` | values before the change (JSON)                      |
| `new_values`      | values after the change (JSON)                       |

`previous_values` / `new_values` store **only the parts that actually changed**: nested hashes and
arrays of hashes are diffed structurally, so a single sub-field change records just that leaf.

The `correlation_key` is the agent's per-request id (`caller.request_id`), generated by the agent and
echoed back to the client in the `X-Forest-Correlation-Id` response header — so every change made in
one request shares a key, and the caller can tie it to its own activity log.

## Options

`ForestAdminAuditTrail::Plugin` options:

| option   | description                                                                          |
| -------- | ------------------------------------------------------------------------------------ |
| `store`  | object responding to `append(record)`. Defaults to a store that only logs.           |
| `redact` | `{ 'collection_name' => ['field', ...] }` — values masked while recording the change |

`SqlStore.new` options: `connection_string:` (required, AR URL or config hash), `schema:`
(default `forest`), `table_name:` (default `audit_logs`).

## Schema migrations & concurrency

The table is created/evolved through an ordered, append-only migration list tracked in a dedicated
`forest.audit_migrations` table. On Postgres the migrations run inside a transaction-scoped advisory
lock so several agents booting at once apply them one after another; the schema is created (and
committed, idempotently) first since the lock can't cover a not-yet-existing schema.

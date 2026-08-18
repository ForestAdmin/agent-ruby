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
| `critical`   | default `false`. `true` refuses an operation the audit trail cannot record — see below |

The store connects and migrates **at boot**, not on the first write: an audit database the agent cannot
reach stops it starting, rather than leaving it looking healthy while recording nothing. Every create /
update / delete performed through Forest then writes one row per record, and the **Historic** tab in the UI
reads from the same table.

## The write protocol, and `critical`

Every operation is recorded twice: a `pending` row **before** the write, confirmed `done` **after** it. One
code path either way, so `status` always means the same thing.

| `critical` | a pending row that cannot be written                                                       |
| ---------- | ------------------------------------------------------------------------------------------ |
| `false`    | is logged and dropped; the operation goes ahead unaudited (the default, today's behaviour)   |
| `true`     | **refuses the operation**. Nothing was written, so there is nothing to repair and no compensating write ever happens |

What this buys is **no unaudited write** — not that every row holds exact after-values. A row left `pending`
means the write may or may not have landed: that residue is evidence, and it is the point. Everything after
the pending insert stays best-effort in both modes, because by then the write has happened and raising would
report a failure for an operation that succeeded.

Consequences worth knowing:

- A write that turns out to change nothing has its pending row **discarded** rather than confirmed, so no-op
  updates leave no trace.
- A record the agent cannot read back after the write keeps its row **pending**. Confirming from the patch
  would claim values that may never have been written.
- One operation audits at most 500 records. Under `critical: false` a wider selection is truncated, with
  `N records audited, M skipped` logged at `Warn`. Under `critical: true` it is **refused**: auditing a subset
  while the write touches every match is precisely the invariant that mode exists for.
- Pending rows stay visible in the history — they are evidence of an attempt, and `status` says so — but the
  state reconstruction ignores them, since undoing a change that may never have happened would invent a state
  the record was never in.

## Routes

All routes live under `/forest/_audit-trail`, are registered only when `audit_trail[:database]` is
set, and require read permission on the target collection (`can?(:read, collection)`).

### Record-history route

`GET /forest/_audit-trail/{collection}/{recordId}` returns the current page of history (newest first
by default) together with the filtered total:

```json
{ "data": [ /* current page rows */ ], "meta": { "count": 137 } }
```

`meta.count` is the number of rows matching the active filters (not the absolute total) and is independent of
the page. `meta.availableUsers` rides along **on the first fetch only** — the front keeps the list it saw —
and holds the distinct authors of the entries the current filters match, as `{ id, firstName, lastName,
email }`, whatever page was asked for. The identity comes from the rows themselves, so someone since renamed
or removed still reads as they were when they acted. Optional filters (all combine with `AND`; omit them for the full history):

| query param | format                           | effect                                          |
| ----------- | -------------------------------- | ----------------------------------------------- |
| `userIds`   | comma-separated integers `12,45` | keep only entries whose `user_id` is in the list |
| `startDate` | `YYYY-MM-DD` or datetime (incl.) | keep entries from this lower bound onward       |
| `endDate`   | `YYYY-MM-DD` or datetime (incl.) | keep entries up to this upper bound             |
| `fields`    | comma-separated field names      | keep only entries whose diff touched one of them |

`fields` matches whole keys, never paths, so a name holding a dot (`address.city`) is quoted before it
reaches SQL. Both sides of the diff are searched, since a field the change added exists in `newValues`
only and one it removed in `previousValues` only. The JSON test is per adapter (Postgres, SQLite, MySQL /
MariaDB); on any other adapter the filter raises rather than silently returning everything.

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

All routes serialize audit records the same way: top-level keys are camelCased — `id`, `recordId`, `userId`,
`userFirstName`, `userLastName`, `userEmail`, `actionName`, `status`, `correlationKey`, `previousValues`,
`newValues`. The row `id` is exposed because both agents order by `(timestamp, id)` and the front uses it as
the merge tiebreaker.

Inside the value objects: a record's column names pass through untouched, while an action answer's keys are
Forest's own and so are camelCase (`mimeType`, not `mime_type`) — the agent transforms them on write.

A record that no longer exists keeps its history: only a record that still exists *outside* the
caller's permission scope is refused (404). Inspecting what was deleted is much of the point of an
audit trail, and the delete event itself is the last thing recorded.

### State route

`GET /forest/_audit-trail/{collection}/{recordId}/state?timestamp=…` returns the record as it stood at
that instant, rebuilt by taking the record as it stands now and undoing every entry recorded **strictly
after** the timestamp — an entry stamped exactly at it counts as part of that state:

```json
{ "data": { "status": "paid", "address": { "city": "Paris" } } }
```

`timestamp` accepts an ISO-8601 instant, or the same wall-clock forms as the filters above read in the
request `timezone`; it is required (**400** otherwise). `data` is `null` when the record did not exist at
that instant — either created later, or deleted and never recreated.

Walking back stops being able to help where the trail stops: only audited (writable) columns are
reconstructed, and a `create` means the record did not exist before it, while a `delete` restores the whole
row it recorded and the walk carries on into any earlier life of the same id.

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

| column           | value                                                                      |
| ---------------- | -------------------------------------------------------------------------- |
| `operation`      | `action` when it went through, `action_failed` when it raised or answered with an `Error` result |
| `previousValues` | the submitted form values (redacted with the same `redact` config)          |
| `newValues`      | what the action answered — an allowlist of the result: `type`, `message`, `name`, `mimeType`, `method`, `url`, `path`. Empty when it raised |
| `recordId`       | each selected record — empty for a global action or a select-all selection  |

The two value columns carry what went in and what came back, rather than a record's before and after. A
result also holds the file's contents, a webhook's body and headers, and arbitrary response headers: file
bytes have no business in an audit table and the other two routinely hold credentials, so the stored answer
is an allowlist — a field added to a result later is not recorded until someone decides it should be. `html`
is left out too, being operator-facing markup the message already summarises.

Because these are the same columns the field filter searches, filtering by a field named like a result key
(`message`, `type`) also matches action rows.

**Which** action ran is not stored: the Forest activity logs already record it, and
`correlationKey` is the join between the two.

A **global** action targets no record, and a **select-all** selection only tells the agent which ids were
*excluded*, so naming the targets would mean querying the whole selection: those runs are recorded once,
attached to no record. Recording is best-effort — a failing audit database logs an error rather than
breaking the action.

The targeted records are read back through the caller's own filter rather than taken from the request: the ids
a client sends are a claim, and in a compliance record asserting that an operator acted on a record their
scope excludes is worse than a missing row.

`url` and `path` are sanitised before storage — credentials in the userinfo and anything in a query string or
fragment come off, since either can carry a signed one-time token that would otherwise sit permanently in the
one table nobody deletes from.

> **What an action changes is only audited when it goes through Forest.** `context.collection.update(...)`
> passes through the same hooks as any other write, so it produces the usual field-level rows sharing the
> action's `correlationKey`. A direct ORM write (`Customer.find(id).update!(...)`) is invisible to the
> agent, so nothing is recorded for it beyond the invocation row above.

## What gets stored

`forest.audit_logs`, one row per audited change:

| column            | description                                                 |
| ----------------- | ----------------------------------------------------------- |
| `id`              | auto-increment primary key, exposed in the payload           |
| `status`          | `pending` before the write, `done` once confirmed            |
| `timestamp`       | when the change happened                                    |
| `operation`       | `create` / `update` / `delete`                              |
| `collection`      | audited collection name                                     |
| `record_id`       | packed record id (primary keys joined by `\|`), TEXT and nullable — a create's pending row has none yet, and a composite id outgrows a varchar |
| `user_id`         | the Forest user who made the change                         |
| `user_first_name`, `user_last_name`, `user_email` | denormalised from the caller at write time: who acted then, not whoever holds that id today |
| `action_name`     | smart-action rows only                                       |
| `correlation_key` | per-request id; groups every change made within one request. Empty for a write outside any request — inventing one would make the row look like a single-row request of its own |
| `previous_values` | values before the change (JSON)                             |
| `new_values`      | values after the change (JSON)                              |

`previous_values` / `new_values` store **only the parts that actually changed**: nested hashes and
arrays of hashes are diffed structurally, so a single sub-field change records just that leaf. Only
writable columns are audited — read-only, computed and DB-managed fields are never written by Forest.

The `correlation_key` is the agent's per-request id (`caller.request_id`), generated by the agent and echoed
back to the client in the `X-Forest-Correlation-Id` response header — so every change made in one request
shares a key, and the caller can tie it to its own activity log.

Outside Rails, mount `ForestAdminAgent::Http::CorrelationIdMiddleware` yourself: it resets the id at the start
of each request, and without it a pooled thread would hand its previous request's key to the next one.

The capture layer registers its **after** hooks ahead of any other customization's (`prepend: true`,
since `execute_after` stops at the first exception, and by then the write has already happened) and its
**before** hooks after them, so the snapshot sees the filter and patch everyone else has had their say on.

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

The table is created and evolved through an ordered, append-only migration list, tracked in a companion table
named after the audited one — `forest.audit_logs_migration` beside `forest.audit_logs`. One tracker per audited
table, so two stores configured with different `table_name`s each keep their own schema history rather than
reading the other's as done.

On Postgres the migrations run inside a transaction-scoped advisory lock, so several agents booting at once
apply them one after another; the schema is created (and committed, idempotently) first, since the lock cannot
cover a schema that does not exist yet.

# Forest Admin — Hasura GraphQL datasource

Surface tables exposed by a [Hasura](https://hasura.io) GraphQL API as Forest Admin collections,
including **Rails-style polymorphic associations** (`belongs_to :commentable, polymorphic: true`).

## Installation

```ruby
# Gemfile
gem 'forest_admin_datasource_graphql_hasura'
```

## Usage

```ruby
ForestAdminRails::Agent.instance.add_datasource(
  ForestAdminDatasourceGraphqlHasura::Datasource.new(
    uri: 'https://my-instance.hasura.app/v1/graphql',
    headers: { 'x-hasura-admin-secret' => ENV['HASURA_ADMIN_SECRET'] }
  )
)
```

Collections are named after the Rails class name derived from the table name
(`transfers` → `Transfer`). This matches the values stored in Rails `*_type` columns, which is
what makes polymorphic relations resolvable by the Forest Admin frontend.

## Polymorphic associations

Rails represents `belongs_to :commentable, polymorphic: true` with two columns
(`commentable_type`, `commentable_id`). Hasura cannot express the type condition, so teams
declare one manual object relationship per target, joining on `commentable_id` alone.

This datasource detects the pattern (a `<base>_type`/`<base>_id` column pair whose object
relationships all join on `<base>_id`) and emits:

- a `PolymorphicManyToOne` (`Comment.commentable`) instead of the ambiguous per-target
  relations — the Forest UI shows the native polymorphic widget;
- a `PolymorphicOneToMany` on each target (`Transfer.comments`, filtered on
  `commentable_type = 'Transfer'`), so related data never leaks records of another type.

The detection uses the Hasura metadata API (`/v1/metadata`, derived from `uri`). When that
endpoint is not reachable (common in production), declare the associations explicitly:

```ruby
ForestAdminDatasourceGraphqlHasura::Datasource.new(
  uri: '...',
  polymorphic_relations: { 'comments' => { 'commentable' => %w[transfers cards] } }
)
```

For namespaced models, override the type value stored by Rails:

```ruby
type_values: { 'bank_accounts' => 'Banking::Account' }
```

## Options

| Option | Description |
| --- | --- |
| `uri` | Hasura GraphQL endpoint (required) |
| `headers` | HTTP headers, e.g. admin secret or JWT |
| `metadata_uri` | Metadata endpoint (default: `uri` with `/v1/graphql` → `/v1/metadata`; not derived — and detection skipped — when `uri` has no `/v1/graphql` segment) |
| `included_tables` / `excluded_tables` | Allow/deny lists of table names |
| `polymorphic_relations` | Explicit polymorphic declarations (see above) |
| `type_values` | Table → Rails class name overrides |
| `timeout` | HTTP timeout in seconds (default 30) |

## Requirements and limitations

- **A polymorphic association is only detected from a Hasura `manual_configuration`
  relationship** joining on the polymorphic foreign key (or from `polymorphic_relations`).
  A relationship backed by a real foreign key constraint is treated as a plain belongs_to,
  so a business enum named `<something>_type` sitting next to a `<something>_id` foreign key
  is left alone.
- **Grouped aggregations** (charts) work on a foreign key, or on a `<relation>:<column>`
  path through a ManyToOne (leaderboard charts) whose reverse relationship is declared in
  Hasura: Hasura exposes GROUP BY only through nested `<relation>_aggregate` fields. A
  foreign key without a declared reverse relationship is advertised as non-groupable, like
  every other column, and date truncation is not supported. Rows whose foreign key is NULL
  form a bucket of their own, as SQL grouping would. Parent rows are filtered by the
  chart's predicate and paginated by 1000; a chart spanning more than 10 000 parent rows
  fails with a clear error rather than returning partial numbers.
- **Tables without a primary key** (typically untracked views) are skipped: Forest cannot
  address their records.
- Filtering and sorting through a polymorphic relation is not possible (a Forest Admin
  limitation shared with the ActiveRecord datasource).
- Pattern operators (`contains`, `starts with`…) are only offered on genuine text columns.
  Postgres enums and custom Hasura scalars get equality and nullity operators, because
  their Hasura comparison expressions have no `_like`/`_ilike`. Text matching is
  case-insensitive, like the ActiveRecord datasource.
- Nested creates/updates are out of scope: mutations write scalar columns (including
  `jsonb`), never related records.
- A `*_type` value matching no exposed collection (a legacy STI subclass name, an excluded
  target) leaves the reference empty and logs a warning, rather than failing the page.
- `bytea` columns are surfaced as text (Hasura returns them hex-encoded).
- Errors Hasura returns (a permission rule, an invalid value) surface as HTTP 400 with the
  original message; an unreachable endpoint (timeout, DNS, TLS, non-2xx response) surfaces
  as HTTP 503, so infrastructure incidents stay visible to monitoring.

## Validating against a real instance

`validation/` holds a Postgres + Hasura stack seeded with a Rails-like schema and an
end-to-end script covering the scenarios above:

```bash
docker compose -f validation/docker-compose.yml up -d
bash validation/setup_hasura.sh
BUNDLE_GEMFILE=Gemfile-test bundle exec ruby validation/validate.rb
```

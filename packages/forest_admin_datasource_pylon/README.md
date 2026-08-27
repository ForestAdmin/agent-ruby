# Forest — Pylon datasource

Surface [Pylon](https://usepylon.com) issues, accounts, contacts, users and teams as Forest
collections, with filters, free-text search, relations, the conversation thread, custom fields,
CRUD writes and two action plugins.

## Installation

```ruby
# Gemfile
gem 'forest_admin_datasource_pylon'
```

## Usage

```ruby
# app/lib/forest_admin_rails/create_agent.rb
ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(
  ForestAdminDatasourcePylon::Datasource.new(api_key: ENV['PYLON_API_KEY'])
)
```

A single Bearer token is the whole configuration. `GET /me` is the health check: it returns the
organization owning the token, which is enough to prove the credentials are usable.

## Collections

| Collection | Pylon resource | Read | Write |
| --- | --- | --- | --- |
| `PylonIssue` | `/issues` | `POST /issues/search`, cursor-paginated | create / update / delete |
| `PylonAccount` | `/accounts` | search + list, cursor-paginated | create / update / delete |
| `PylonContact` | `/contacts` | search + list, cursor-paginated | create / update / delete |
| `PylonUser` | `/users` | whole dataset, unpaginated | update |
| `PylonTeam` | `/teams` | whole dataset, unpaginated | create / update |

`PylonIssue`, `PylonAccount` and `PylonContact` also carry their Pylon custom fields, introspected
at boot from `GET /custom-fields`.

## What the API cannot do, and what this does about it

Pylon is a ticketing API, not a database, and several things Forest asks for have no equivalent.
Where that happens this datasource **refuses with a message naming the reason** rather than
answering something that looks right and is not. All of these arrive as a 400 carrying the text.

- **No aggregate endpoint and no total.** `aggregate` is refused on the cursor-backed collections:
  counting the pages a walk collected would answer a fraction of a collection as if it were the
  whole of it. No collection is advertised as countable.
- **No sort parameter on `/issues/search`.** Issues always come back newest first. A requested
  order is reported in the log rather than silently swallowed.
- **No `id` filter on the search endpoints.** A primary-key lookup is short-circuited to
  `GET /issues/{id}`, one request per id. That fan-out is capped per page (`MAX_ID_LOOKUPS`), and
  a selection naming more ids *and* filtering them further is refused, since which records the
  page holds could only be known by reading all of them.
- **No joins.** A condition on a relation is answered by reading the foreign collection for its
  keys and sending them as an `in`. Past `MAX_RELATION_KEYS` the condition is refused.
- **Search and id lookup are different endpoints.** Combining a free-text search with a filter on
  `id` is refused: neither endpoint can do the other's half.
- **Writes are one record per request.** A write reaching more records than one pass covers is
  refused up front; one that fails halfway reports exactly which records were written, so a retry
  can target the untouched ones rather than performing the write twice.

## Rate limits

Pylon meters **per endpoint**, not per token, from 30 to 300 requests a minute depending on the
endpoint. `RateLimits` holds the documented budget of every endpoint this client calls, and
`RateLimiter` spaces requests out so each one is spent rather than exceeded — a sliding window per
endpoint, in front of the 429 retry rather than instead of it.

The limiter is a smoother, not a guarantee: past `DEFAULT_MAX_WAIT` a request goes out anyway and
the 429 retry takes over, with one log line per endpoint per window saying so. Under real
saturation — several agents or processes on the same token — the retry is the defence.

To meter on your own side instead, pass `rate_limiter: nil`:

```ruby
ForestAdminDatasourcePylon::Datasource.new(api_key: ENV['PYLON_API_KEY'], rate_limiter: nil)
```

## Boot-time introspection

Custom fields are read while the datasource is being constructed, one call per object type. That
sits in front of a Rails boot, so it runs on its own connection with short timeouts and a single
quick retry (`boot_open_timeout`, `boot_timeout`, `boot_retry_policy`), and the first failure
stops the remaining object types from being tried.

An introspection that fails costs the custom columns, not the datasource: the agent boots on the
native schema and says so in the log.

## Action plugins

### `CloseIssue`

Moves the selected issues to a state, single and bulk, one request per issue with a per-id rescue
so one failure does not abort the batch.

```ruby
@agent.collection :Ticket do |collection|
  collection.use(ForestAdminDatasourcePylon::Plugins::CloseIssue, {
    datasource: pylon_datasource,        # required
    issue_id_field: 'pylon_issue_id',    # omit when the action sits on PylonIssue itself
    state: 'closed',                     # default
    scopes: %i[single bulk]              # default
  })
end
```

Two things to know before granting it. The state is written straight through the Pylon client
rather than through `PylonIssue`, because the action is registered on the host collection: a Forest
scope or segment restricting `PylonIssue` therefore does **not** bound what this closes — the
records the operator may see on the host collection do. And the batch is one request per selected
record with no cap, so a wide bulk selection is a long run of sequential writes that the request
may time out on, leaving the issues closed up to that point closed. Restrict the action, or the
selection, accordingly.

### `CreateIssueWithNotification`

Creates an issue from a form and notifies the requester, optionally writing the new issue id back
onto the host record.

```ruby
@agent.collection :Customer do |collection|
  collection.use(ForestAdminDatasourcePylon::Plugins::CreateIssueWithNotification, {
    datasource: pylon_datasource,        # required
    sender_email: 'support@example.com', # required when the destination is email
    issue_id_field: 'pylon_issue_id',    # optional id writeback
    email_templates: [{ title: 'Outage', content: '<p>Sorry {{ record.name }}</p>' }]
  })
end
```

`{{ record.field }}` tokens are interpolated from the host record, HTML-escaped in the message
body. Template titles must be unique and cannot be `"No template"`, which names the option that
picks none of them.

The message body is HTML the operator writes and Pylon delivers to the requester, and the
requester address is a free-text field. Restrict both actions to the roles that should be able to
send mail on your organization's behalf.

## Development

```bash
cd packages/forest_admin_datasource_pylon
bundle install
bundle exec rspec
bundle exec rubocop
```

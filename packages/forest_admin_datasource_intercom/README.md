# Forest — Intercom datasource

Surface [Intercom](https://www.intercom.com) conversations, tickets, teammates, teams, ticket types
and ticket states as Forest collections.

This is **lot 1: read only**. Rows, record details, exact counts and the conversation thread work;
server-side filtering, writes, business actions, contacts and companies arrive in the lots after it
— see "What is not here yet".

## Installation

```ruby
# Gemfile
gem 'forest_admin_datasource_intercom'
```

## Usage

```ruby
# app/lib/forest_admin_rails/create_agent.rb
ForestAdminAgent::Builder::AgentFactory.instance.add_datasource(
  ForestAdminDatasourceIntercom::Datasource.new(
    access_token: ENV['INTERCOM_ACCESS_TOKEN'],
    region: :eu # :us (default), :eu or :au
  )
)
```

The token is the access token of a private app, created in Intercom's Developer Hub under
*Configure › Authentication*. OAuth is out of scope: it belongs to a control plane distributing a
connector, not to an agent reading one workspace.

`Client#me` is the health check — it returns the admin the token belongs to, and is the one call
that verifies the pinned API version was honoured.

### Configuration

| Option | Default | What it is for |
| --- | --- | --- |
| `access_token` | — | Required. The private app's bearer token. |
| `region` | `:us` | `:us`, `:eu`, `:au`. A workspace answers in its own region only. |
| `base_url` | from `region` | Wins over `region`. For an egress proxy or a mock server. |
| `api_version` | `'2.16'` | Sent as `Intercom-Version` on every request. |
| `open_timeout` / `timeout` | `5` / `30` | A request that already has a page on screen. |
| `boot_open_timeout` / `boot_timeout` | `3` / `10` | The one read performed while the agent starts. |
| `retry_policy` | `RetryPolicy.new` | Statuses, verbs and backoff. |
| `boot_retry_policy` | `RetryPolicy.boot` | One quick retry; gives up rather than waiting a 429 out. |
| `rate_limiter` | `RateLimiter.new` | `nil` takes the pacing out of the stack. |

**Pin the region explicitly.** `api.intercom.io` does route to the right one, but a workspace under
GDPR wants its requests reaching the European host and nothing else.

**The version is pinned on purpose.** Without the header a request follows the workspace's own
default version, which an operator can change on Intercom's side — and the payloads change shape
underneath. Intercom echoes the version it served, so `me` compares the two and logs a warning when
the pin was not honoured, rather than raising: running against a version we did not ask for still
beats not running.

### Token permissions

A read-only token is enough, and is what to recommend for this lot. A permission the token lacks
costs **columns or a collection, never the boot of the agent**: the ticket-type introspection
degrades to no attribute column, and a collection whose endpoint answers 403 fails its own page.

## Collections

| Collection | Endpoint | Paginated | Countable |
| --- | --- | --- | --- |
| `IntercomConversation` | `GET /conversations`, `POST /conversations/search`, `GET /conversations/{id}` | cursor | yes, exactly |
| `IntercomTicket` | `POST /tickets/search`, `GET /tickets/{id}` | cursor | yes, exactly |
| `IntercomAdmin` | `GET /admins` | read whole | yes, exactly |
| `IntercomTeam` | `GET /teams` | read whole | yes, exactly |
| `IntercomTicketType` | `GET /ticket_types` | read whole | yes, exactly |
| `IntercomTicketState` | `GET /ticket_states` | read whole | yes, exactly |

Two tiers, and they behave differently on purpose.

**Read whole** — admins, teams, ticket types, ticket states. Their endpoints answer in one response,
so filtering, sorting, paging and counting them in memory is *exact*: the records in hand are every
record Intercom holds. These are the only collections that can be filtered, sorted and grouped in
this lot, and the only ones a chart may group by. The cost is bandwidth, not correctness.

**Cursor** — conversations and tickets. What is in hand is a page of something far larger, so
nothing is filtered or sorted in memory. Three routes and no fourth: no condition walks the listing,
`id equals X` reads the record through its own endpoint, and anything else is translated into
Intercom's search DSL and walked through the search endpoint. What the translation cannot express is
**refused by name** — see [Filtering](#filtering).

## What the API cannot do, and what this does about it

Where Forest asks for something Intercom has no equivalent for, this datasource **refuses with a
message naming the reason** rather than answering something that looks right and is not. Those
arrive as a 400 carrying the text.

- **No offset pagination.** Intercom hands out the page after a cursor and documents that jumping to
  page N is unsupported, so reaching page 20 costs 20 sequential requests. The walk is capped at 50
  pages / 7 500 records and every truncation is logged, naming the window it stopped in.
- **Duplicates on a moving dataset.** Intercom documents that records modified between two paginated
  requests can be served twice; the walk deduplicates by id. The missed counterpart is inherent to
  cursor pagination and cannot be repaired — it is documented rather than papered over.
- **A search takes no sort at all.** Neither search endpoint accepts one, so **no column of
  `IntercomConversation` or `IntercomTicket` is sortable** and an explicit order is reported in the
  log. The only collections Intercom sorts are the ones read whole, in memory.
- **A sort is accepted and ignored.** Measured: `sort` on these endpoints raises nothing and changes
  nothing. Since the lack of support is undetectable at runtime, no column is declared sortable and
  a requested order is reported in the log. The rows come back in the order the API imposes.
- **No aggregate endpoint.** Counting is free and exact — `total_count` counts what the query names,
  not what a page held — so the record counter is one request. Anything beyond a count is refused on
  the cursor collections: grouping over the pages a walk collected would look exact while answering
  a fraction.
- **`per_page` is refused past 150**, with `invalid_per_page` and no silent downgrade, so the page
  size is bounded before the request leaves. Tickets are bounded far lower still: **25**, because
  the search response carries the whole timeline of every ticket and Intercom offers no field
  selection. Provisional, pending measurement against real response sizes.
- **No `GET /tickets` at all.** Even an unfiltered ticket list goes through `POST /tickets/search`
  with a predicate matching everything.
- **The envelope key is not always `data`.** Measured: `/tickets/search` answers under `tickets`,
  `/admins` under `admins`, `/teams` under `teams`. A response carrying neither the expected key nor
  `data` is refused rather than read as an empty page.

## Filtering

`POST /conversations/search` and `POST /tickets/search` answer the condition trees Forest sends, on
the fields Intercom really filters and with the operators each endpoint really validates. Anything
else is **refused with a message naming what to change** — a condition dropped on the way out comes
back as an unfiltered page that looks filtered, which is the one answer this datasource must not
give. A refusal costs no request: it is raised before anything leaves the process.

### The table is measured, not documented

The fields a search endpoint filters are not the fields its specification lists. Measured:
`/tickets/search` refuses `company_id` with `invalid_field` although every ticket carries one. So
the source of truth is a committed table — `lib/forest_admin_datasource_intercom/query/search_fields.yml`
— one row per column, each carrying its provenance:

| `source` | What it means |
| --- | --- |
| `measured` | observed against a real workspace, by `bin/probe_search_fields` or during the spike |
| `spec` | read off Intercom's documentation, and therefore still a candidate |

Every `filter_operators` a column publishes is **derived** from that table, so a column cannot
advertise a filter the translator would then refuse, and a column the table does not carry
advertises nothing at all.

To measure a workspace of your own:

```bash
INTERCOM_ACCESS_TOKEN=... bin/probe_search_fields --endpoint tickets --out measured.yml
```

It sends one search per (field, operator) cell, reads Intercom's refusal codes — `invalid_field` for
a field the endpoint does not filter, `data_invalid` for an operator it refuses on that field — and
prints what the committed table promises that Intercom refuses, plus what Intercom accepts that the
table does not know about. It writes evidence rather than rewriting the table, which carries the
prose a generated file would drop.

### A date filter is day-granular, and the day is the UTC one

Intercom truncates a date search to the day, at the **UTC** boundary — measured, and against its own
documentation, which promises the workspace's timezone. `> V` answers from the start of the day
*after* V; `< V` answers before the start of V's own day.

Sent as they come, the two bounds an interval is rewritten into cancel each other out: `today`
reaches the datasource as `> 00:00` and `< 23:59` of one day, which Intercom reads as "from
tomorrow" *and* "before today" — no rows at all, to the most ordinary filter there is. So each bound
is moved to the boundary that makes Intercom answer the day the filter named.

What follows from that:

- a bound naming a time of day matches **from the start of that day, or through the end of it**. It
  is the granularity the Intercom interface itself filters on;
- a caller in UTC gets exactly the day they asked for;
- a caller in another timezone gets the UTC days their window overlaps — up to a day wider at each
  end — and the agent logs that once per filter;
- a date column publishes `>` and `<` only, and no equality. Everything an operator actually uses —
  `before`, `after`, `today`, `yesterday`, `past`, `future`, the whole `previous_*` family — is
  rewritten by the agent into a pair of those bounds. An equality on an instant is what stays out,
  and a day-granular filter could not have honoured it anyway.

### What is filterable

| Collection | Filterable on |
| --- | --- |
| `IntercomConversation` | `state`, `priority`, `open`, `read`, `title`, `admin_assignee_id`, `team_assignee_id`, `source_type`, `source_subject`, `source_body`, `source_delivered_as`, `source_author_email`, `closed_by_id`, `reopen_count`, `part_count`, `ai_agent_participated`, and the dates `created_at`, `updated_at`, `waiting_since`, `snoozed_until`, `closed_at`, `first_closed_at`, `first_contact_reply_at`, `last_contact_reply_at`, `last_admin_reply_at` |
| `IntercomTicket` | `open`, `category`, `ticket_type_id`, `admin_assignee_id`, `team_assignee_id`, `created_at`, `updated_at` |

**Free-text search** is answered on `IntercomConversation` only, through `~` on `source.body` — the
message that opened the conversation. Intercom matches it **per word, not as a substring**: searching
`fact` does not find `facture`. `IntercomTicket` exposes no text column this endpoint matches and
refuses a search by name.

### What is not filterable, and why

- **the columns a ticket derives from its parts** — `closed_at`, `closed_by_name`, `last_reply_at`,
  `last_responder_name`, `last_responder_type`. They exist nowhere in Intercom; `/tickets/search`
  filters none of them and ignores a sort on them without a word;
- **the account of a ticket** — `company_id`, refused by the endpoint itself with `invalid_field`;
- **the ticket attributes** — filtered as `ticket_attribute.{id}`, and the same attribute carries a
  different id per ticket type, so a union column has no single id to translate to. See
  [Tickets](#tickets);
- **the tag names, the company name and the contact identity of a conversation** — read from
  somewhere the search endpoint does not filter, or filtered by an id the column does not hold;
- **absence** — `present`, `blank` and `missing` are derived by the agent from an equality and
  rewritten into a comparison with an empty value. Intercom's search matches values and has no
  operator for the lack of one, so the rewritten condition is refused rather than sent as a
  comparison against the empty string;
- **group-by**, on either cursor collection: there is no aggregate endpoint, and grouping over the
  pages a walk collected would look exact while answering a fraction.

### The limits of a search, checked before the request leaves

Intercom nests a search **two levels** deep and takes **fifteen conditions per group**. Past either
it answers a 400 whose body names neither the limit nor the part of the filter that reached it, so
both are checked here and refused with a message naming what to simplify.

Fifteen is reached without trying: a scope, a segment and an operator's own filter add up, and a
condition naming several values arrives expanded into **one condition per value** — Intercom accepts
no membership operator on these fields. Branches carrying a single condition are unwrapped and spend
no level.

## Conversations

The row carries what a queue is read for: state, priority, assignee and team ids, the company, the
tags, and the lifecycle Intercom keeps in `statistics` — `closed_at`, `closed_by_id`,
`first_contact_reply_at`, `last_contact_reply_at`, `last_admin_reply_at`, `reopen_count`.

**The timeline opens on `source`, not on the parts.** The message that started the conversation
lives there; a thread built from the parts alone opens on the first reply and loses what the
customer actually asked. Every entry keeps its `part_type` — an assignment, a note and a reply are
different events.

Intercom returns the parts **only when retrieving a single conversation**, so:

- a record detail gets its timeline for free;
- a list view asking for the `timeline` column pays one request per row, bounded to 10. The rows past
  that keep a `nil`, which reads as *unknown* — never as an empty thread.

A conversation is capped at its **500 most recent parts**; a very long thread is therefore partial,
and says so nowhere but here.

Contact name and e-mail are denormalized onto the row by **one bulk read per page**, not one per
row, and only when the projection names them. A failure there costs those two columns, not the page.

## Tickets

A ticket carries **no `statistics` block** — measured against a workspace of 81 142 tickets — so
neither a closure date nor a last responder exists as a field. Both are derived from the parts,
which ride along in the search response whether or not anything asks for them, and therefore cost
nothing:

| Column | Derived from |
| --- | --- |
| `closed_at`, `closed_by_name` | the last transition into a state of category `resolved` |
| `last_reply_at`, `last_responder_name`, `last_responder_type` | the last `comment` part |

Four things to know about them:

- a ticket is not "closed" on Intercom, it enters a **resolved** state;
- the state-change event is matched on its **prefix**, not on `ticket_state_updated_by_admin`: a
  workspace running workflows closes tickets through other variants, and an invisible closure is
  worse than an absent column;
- a transition whose target equals the previous state is ignored — measured, they exist;
- **a resolved ticket showing no closure date may have been closed all the same**: past the 500-part
  ceiling the transition falls out of the window. That case is detected and logged, since a Date
  column cannot say "unknown".

Both are **display only**, and not temporarily: `/tickets/search` filters on neither and ignores a
sort, so neither advertises an operator.

The attributes a workspace declares on its ticket types are introspected once at boot and published
as the **union** of every type's, keyed by name the way the payload is. Filtering one is a different
matter: Intercom filters an attribute by id (`ticket_attribute.{id}`), and the same name carries a
different id from one ticket type to the next — measured, `_default_title_` is `14162161` on one
type and `14162165` on another. A union column has no single id to translate to, so filtering on a
ticket attribute means one collection per ticket type — more collections in the interface, and a
schema that changes shape whenever the customer adds a type. Until that trade is worth paying for,
the attributes stay display-only and advertise no operator. The ids are kept per type so the day the
answer changes costs no second boot round trip.

## Rate limits

Intercom meters the app and, above it, the whole workspace — 25 000 requests a minute shared with
every other private app the customer runs — and allocates that budget in **10-second windows**: the
measured `x-ratelimit-limit` is 1667, not 10 000. A burst therefore takes a 429 while the minute's
budget is barely touched, which is why what matters is the instantaneous rate.

The limiter is driven by the headers Intercom returns on every response rather than by a table: it
waits out the reset when the window is spent, and counts its own in-flight requests down so several
of them do not go out on the same stale figure. A reset further out than a window is a clock
disagreement rather than a window emptying — the request goes through and the log says so, once per
window.

It sits **in front of** the 429 retry, not instead of it: the retry remains the defence against the
part of the workspace budget spent by traffic this process cannot see. Pass `rate_limiter: nil` to
meter on your own side instead.

## Privacy

The body of a conversation is raw personal data, and this datasource is built on that assumption.

- **Nothing logs a body.** Logs carry the operation, the counts and Intercom's request id — never
  content. A response that fails to parse is reported by name, never quoted: a JSON parser opens its
  message with the characters it choked on, and on a 200 those are the payload.
- **`display_as=plaintext` on every conversation read.** The bodies are HTML written by end
  customers; rendering third-party HTML inside Forest is neither safe nor useful.
- **The regional host is configurable** so a workspace's data stays in its region.
- Ticket list pages carry customer message bodies whether or not anything asks for them — Intercom
  offers no field selection. Restrict the body columns with Forest's field-level permissions where
  that matters.

## Boot-time introspection

Constructing the datasource performs exactly **one** read: `GET /ticket_types`, for the attribute
columns of `IntercomTicket`. It runs on the boot connection — short timeouts, one quick retry — so a
slow Intercom cannot turn a Rails boot into minutes the operator sits through, and it degrades to no
attribute column rather than to a failed boot.

Everything else is read when a collection is listed, so an agent boots whatever Intercom is doing.

## What is not here yet

| Lot | What it brings |
| --- | --- |
| 3 | Writes and business actions: reply, close, snooze, reopen, assign, tag, convert |
| 4 | Contacts and companies, and the relations promoted from today's denormalized columns |
| 5 | Notes, tags, segments |
| 6 | Bounded group-by and the reporting export |

## Development

```bash
cd packages/forest_admin_datasource_intercom
BUNDLE_GEMFILE=Gemfile-test bundle install
BUNDLE_GEMFILE=Gemfile-test bundle exec rspec
bundle exec rubocop # from the repository root
```

Specs stub the HTTP layer with WebMock. Every payload they feed in is **hand-written from the
OpenAPI 2.16 specification**, never captured from a workspace: a conversation body is personal data,
and a fixture is read by everyone who clones the repository.

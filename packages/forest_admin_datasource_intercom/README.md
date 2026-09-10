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
costs **columns or a collection, never the boot of the agent**: the three boot-time introspections
each degrade to no attribute column, a collection whose endpoint answers 403 fails its own page, and
a token that cannot read `/admins` or `/teams` leaves the `admin_names` / `team_names` column empty
rather than failing the page it is on. A token denied contacts or companies costs those two
collections and the `contact_name` column, and leaves everything else standing.

A **relation is the exception**, and it is worth knowing before scoping a token: resolving one reads
the target endpoint, and that read is not guarded the way the names above are. A token denied
`/admins` fails any page projecting `admin_assignee:name`, and fails the related list behind
`IntercomTeam#admins` — the failure lands on the collection being read, not on the one that was
denied. Scope the token to the endpoints in the table below, or to none of them.

## Collections

| Collection | Endpoint | Paginated | Countable |
| --- | --- | --- | --- |
| `IntercomConversation` | `GET /conversations`, `POST /conversations/search`, `GET /conversations/{id}` | cursor | yes, exactly |
| `IntercomTicket` | `POST /tickets/search`, `GET /tickets/{id}` | cursor | yes, exactly |
| `IntercomAdmin` | `GET /admins` | read whole | yes, exactly |
| `IntercomTeam` | `GET /teams` | read whole | yes, exactly |
| `IntercomTeamMembership` | `GET /teams` | read whole | yes, exactly |
| `IntercomTicketType` | `GET /ticket_types` | read whole | yes, exactly |
| `IntercomTicketState` | `GET /ticket_states` | read whole | yes, exactly |
| `IntercomContact` | `GET /contacts`, `POST /contacts/search`, `GET /companies/{id}/contacts` | cursor | yes, exactly |
| `IntercomCompany` | `POST /companies/list`, `GET /companies?...`, `GET /companies/{id}` | **offset** | yes, exactly |

Three tiers, and they behave differently on purpose.

**Read whole** — admins, teams, team memberships, ticket types, ticket states. Their endpoints answer in one response,
so filtering, sorting, paging and counting them in memory is *exact*: the records in hand are every
record Intercom holds. These are the only collections that can be filtered, sorted and grouped in
this lot, and the only ones a chart may group by. The cost is bandwidth, not correctness.

**Cursor** — conversations, tickets and contacts. What is in hand is a page of something far larger,
so nothing is filtered or sorted in memory. Three routes and no fourth: no condition walks the
listing, `id equals X` reads the record through its own endpoint, and anything else is translated
into Intercom's search DSL and walked through the search endpoint. What the translation cannot
express is **refused by name** — see [Filtering](#filtering). Contacts add two routes of their own,
both described under [Contacts](#contacts).

**Offset** — companies, and nothing else. `POST /companies/list` takes a **page number**, which is
what a list view asks for: page 7 is one request rather than six pages walked to reach it, with no
cap and no truncation warning. It is the one place the [first limitation
below](#what-the-api-cannot-do-and-what-this-does-about-it) does not apply. What it pays for that is
filtering — there is no company search endpoint at all, so what a filter may say is a handful of
exact lookups and nothing else. See [Companies](#companies).

## Relations

Intercom joins nothing: a ticket carries an assignee id, and the teammate behind it is a second read
of a second endpoint. What makes these relations affordable is what the collection on the far end
costs to read by id, and the three tiers do not cost the same:

| Target | Read by id | A page of rows costs | Fan-out |
| --- | --- | --- | --- |
| `IntercomAdmin`, `IntercomTeam`, `IntercomTicketState`, `IntercomTicketType` | read whole | **one request**, whatever the page holds | unbounded |
| `IntercomContact` | `id IN [...]`, 100 at a time | one request per 100 distinct contacts | unbounded |
| `IntercomCompany` | `GET /companies/{id}` | **one request per distinct account** | bounded, see below |

The price is per target *collection*, not per relation: a ticket's `state` and `previous_state` are
one read of `/ticket_states`, over the ids both of them name.

**The one relation with a ceiling is `IntercomContact#company`.** There is no bulk read for a
company — `/companies/scroll` is [deliberately rejected](#companies) — so each distinct account on
the page costs a request, and past
[`MAX_RELATION_READS`](lib/forest_admin_datasource_intercom/collections/offset_collection.rb)
distinct accounts the read is **refused by name** rather than resolved for the first slice and left
nil for the rest. Every page size a list view offers sits under that figure; an export or a segment
resolved whole does not, and the message says to leave the column out or read fewer rows at a time.
The alternative — a nil where an account exists — is the one answer this datasource must not give,
and a log line nobody reads is not a substitute for it.

*Exactly*, with one more bound worth naming: "read whole" is what the endpoint answers, and
`fetch_all` stops after [`MAX_COLLECTED_PAGES`](lib/forest_admin_datasource_intercom/client.rb) pages
if Intercom paginates one of these on its own — it logs when it does. A workspace whose `/admins` or
`/teams` runs past that cap resolves the relations pointing at the records it dropped as empty. The
figure is sized for reference collections, which is what the first tier above is.

| Collection | Relation | Target | Filterable through |
| --- | --- | --- | --- |
| `IntercomConversation` | `admin_assignee`, `closed_by` | `IntercomAdmin` | yes |
| `IntercomConversation` | `team_assignee` | `IntercomTeam` | yes |
| `IntercomTicket` | `admin_assignee` | `IntercomAdmin` | yes |
| `IntercomTicket` | `team_assignee` | `IntercomTeam` | yes |
| `IntercomTicket` | `ticket_type` | `IntercomTicketType` | yes |
| `IntercomTicket` | `state`, `previous_state` | `IntercomTicketState` | **no** — read and navigate only |
| `IntercomTeam` | `admins` | `IntercomAdmin` | no (many-to-many) |
| `IntercomAdmin` | `teams` | `IntercomTeam` | no (many-to-many) |
| `IntercomTeamMembership` | `team`, `admin` | `IntercomTeam`, `IntercomAdmin` | yes |
| `IntercomConversation` | `contact` | `IntercomContact` | yes |
| `IntercomTicket` | `contact` | `IntercomContact` | **spec, unprobed** — see below |
| `IntercomContact` | `owner` | `IntercomAdmin` | yes |
| `IntercomContact` | `company` | `IntercomCompany` | **no** — read and navigate only |
| `IntercomContact` | `conversations`, `tickets` | `IntercomConversation`, `IntercomTicket` | no (one-to-many) |
| `IntercomCompany` | `contacts` | `IntercomContact` | no (one-to-many) |

Every one of them is **read-only**: this lot writes nothing, and Intercom exposes no endpoint that
writes a team membership at all.

**`IntercomTeamMembership` exists because Intercom's does not.** The workspace carries the
membership on the team (`admin_ids`) and on the teammate (`team_ids`) both and exposes no resource
for the pair, while a many-to-many needs a collection to travel through. It is synthesized from
`GET /teams`, one record per pair, keyed `teamId:adminId`. Without it, both sides read as an array of
ids nobody can click.

Two consequences of travelling through it are worth knowing. A **related list of teammates is
ordered by the membership, not by the teammate**: the agent hands the through collection the columns
of the collection the relation reaches, so an order on `name` or `email` cannot be resolved there and
is logged rather than silently dropped. And a `admin_ids` entry naming a teammate `/admins` does not
answer -- one who left, one outside the token's reach -- **drops out of the related list** instead of
appearing as an empty row.

Alongside it, a team names its teammates (`admin_names`) and a teammate its teams (`team_names`) on
the row itself, so a list view reads without a join. **Those replace the arrays of ids** the first
lots published: one readable form plus a relation to navigate, rather than two ways to read one fact.
They are read only when a projection asks for them, and a token that cannot read the other side
costs the column and nothing else — never the page, and never the relation.

**The 360 degrees is those last four rows.** From a ticket or a conversation, `contact` reaches the
person who wrote in; from them, `conversations` and `tickets` list everything they ever opened, and
`company` reaches their account, whose `contacts` lists their colleagues. Each of those lists is one
request: `/conversations/search` matches a conversation against one of its contact ids, and
`GET /companies/{id}/contacts` answers the contacts of an account — which is the one relation
`/contacts/search` could not have resolved, filtering no company field.

**A conversation has several contacts, and the relation names the first of them** — the same one
`contact_name` and `contact_count` describe, so the column and the relation cannot disagree. The
others are a hop away: open that contact and read their conversations. The alternative, a
many-to-many through a join collection, would have been the honest cardinality at the price of three
collections of plumbing in the interface; naming the first contact and counting them is what lot 1
already published, and lot 4 promotes it rather than replacing it.

Two of these carry a caveat worth reading before scoping a token or writing a segment. The **ticket
side is a `spec` row the probe has not confirmed**: whether `/tickets/search` filters on
`contact_ids` at all is unmeasured, and if it does not, the relation stays navigable and the filter
moves to the refusal table — exactly what happened to the ticket `state`. And **the company
traversal is refused by name**: `/contacts/search` filters no company field, so `company:name` is
answered with a message saying to filter from the company side instead.

The same rule settled the ticket labels: `state_label` and `ticket_type_name` stay on the row,
`state_category` and `state_external_label` are gone — they are a hop away, on the `state` relation,
and neither was ever filterable, so no segment, scope or saved filter could rest on them.

A relation reads its target **undecorated**, so a permission scope or a segment defined on the target
does not narrow what a relation resolves — the same way a native datasource joins a table without
applying the scopes of the collection mapped to it.

One semantic worth stating plainly: **a row whose foreign key is null matches no relation filter**,
the way a join drops it, negated filters included. A ticket with no assignee is not "assigned to
someone other than Marie".

## What the API cannot do, and what this does about it

Where Forest asks for something Intercom has no equivalent for, this datasource **refuses with a
message naming the reason** rather than answering something that looks right and is not. Those
arrive as a 400 carrying the text.

- **No offset pagination, except on companies.** Intercom hands out the page after a cursor and
  documents that jumping to page N is unsupported, so reaching page 20 costs 20 sequential requests.
  The walk is capped at 50 pages / 7 500 records and **every route out of it that is short of what
  was asked for is logged**, naming the window it stopped in: the two caps, and the two defensive
  stops — a page that advertises a next cursor and holds nothing, and a cursor already followed.
  Intercom does neither of the last two today, which is exactly why they are reported rather than
  taken for the end of the data. `POST /companies/list` is the exception and takes a page number,
  which is why companies escape the walker and its caps entirely.
- **Duplicates on a moving dataset.** Intercom documents that records modified between two paginated
  requests can be served twice; the walk deduplicates by id. The missed counterpart is inherent to
  cursor pagination and cannot be repaired — it is documented rather than papered over.
- **One endpoint sorts, and it is `/contacts/search`.** Everything else comes back in the order the
  API imposes: `POST /companies/list` has no order parameter at all, and the other two search
  endpoints **accept a `sort` and ignore it** — measured, it raises nothing and changes nothing.
  Since that is undetectable at runtime, no column of `IntercomConversation`, `IntercomTicket` or
  `IntercomCompany` is declared sortable and a requested order is reported in the log. The
  collections read whole sort in memory, exactly, and Contacts sort server-side on the columns the
  measured table declares — see [Contacts](#contacts). One route of Contacts cannot carry it either:
  a read by id cuts the window in the order the ids were named, so ordering what comes back would
  order a slice picked by something else. That order is reported in the log too.
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

### The table is data, and it says where each row comes from

The fields a search endpoint filters are not the fields its specification lists. Measured:
`/tickets/search` refuses `company_id` with `invalid_field` although every ticket carries one. So
the source of truth is a committed table — `lib/forest_admin_datasource_intercom/query/search_fields.yml`
— one row per column, each carrying its provenance:

| `source` | What it means |
| --- | --- |
| `measured` | observed against a real workspace, by `forest_admin_intercom_probe` or during the spike |
| `spec` | read off Intercom's documentation, and therefore still a candidate |

Every `filter_operators` a column publishes is **derived** from that table, so a column cannot
advertise a filter the translator would then refuse, and a column the table does not carry
advertises nothing at all. That is the mechanism, and it holds whatever the rows say.

**What the rows say today is mostly `spec`: 18 of 89 are measured, and no endpoint has been probed
end to end** — all three carry `measured_at: null`, which is what `Endpoint#measured?` reports. The
measured rows are the ones a spike went out of its way to check: the date operators on each
endpoint, which disagree between them, `id IN` on `/contacts/search`, `contact_ids` on
`/conversations/search`, and the refusals a read confirmed — `company_id` on `/tickets/search`
above all, alongside the columns the agent derives rather than reads. Everything else is Intercom's
documentation, and the disagreement above is why that is a candidate rather than a promise. Those
two figures are asserted against the file, so they cannot drift from it.

So the first thing to do against a customer's workspace is to run the probe. The rows worth watching
first, in the order they will hurt:

1. **`admin_assignee_id` and `team_assignee_id`**, on both search endpoints. Typed `string` here;
   Intercom documents them as `Integer` and answers `data_invalid` on a value whose type it does not
   accept. These carry the `admin_assignee` and `team_assignee` relations — the filter an ops team
   reaches for first — so a wrong type here is the most expensive `spec` row in the file;
2. **`state_id` on `/tickets/search`** — the table carries no filter on it at all, which is what
   keeps the `state` relation read-only. If the endpoint does filter one, a support queue becomes
   filterable by state;
3. **`contact_ids` on `/tickets/search`** — the contact relation of a ticket rests on it;
4. **the operators Intercom answers on `custom_attributes.{name}`**, per data type, which is the only
   thing keeping those columns display-only;
5. **whether `POST /conversations/search` honours `display_as=plaintext`** — it is sent either way,
   and an ignored parameter costs a query string where the honoured one saves every filtered row
   from coming back as markup.

To measure a workspace of your own. The probe ships with the gem — it is what measures the
customer's workspace, and whoever runs it there has the gem installed rather than a clone of
`agent-ruby` — so `bundle install` puts it on the path of the application the datasource is
mounted in:

```bash
INTERCOM_ACCESS_TOKEN=... bundle exec forest_admin_intercom_probe --endpoint tickets --out measured.yml
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
| `IntercomConversation` | `id`, `state`, `priority`, `open`, `read`, `title`, `admin_assignee_id`, `team_assignee_id`, `source_type`, `source_subject`, `source_body`, `source_delivered_as`, `source_author_email`, `closed_by_id`, `reopen_count`, `part_count`, `ai_agent_participated`, `contact_id`, and the dates `created_at`, `updated_at`, `waiting_since`, `snoozed_until`, `closed_at`, `first_closed_at`, `first_contact_reply_at`, `last_contact_reply_at`, `last_admin_reply_at` |
| `IntercomTicket` | `id`, `open`, `category`, `ticket_type_id`, `admin_assignee_id`, `team_assignee_id`, `contact_id`, `created_at`, `updated_at` |
| `IntercomContact` | `id`, `role`, `name`, `email`, `email_domain`, `phone`, `external_id`, `owner_id`, `unsubscribed_from_emails`, `has_hard_bounced`, `marked_email_as_spam`, `language_override`, `browser`, `browser_language`, `os`, `location_country`, `location_region`, `location_city`, and the dates `created_at`, `updated_at`, `signed_up_at`, `last_seen_at`, `last_contacted_at`, `last_replied_at`, `last_email_opened_at`, `last_email_clicked_at` |
| `IntercomCompany` | `id`, `company_id`, `name` — four lookups and no search endpoint, see [Companies](#companies) |

**The primary key** is filterable like any other column, but a filter naming it *alone* is not
answered by a search: `id equals X` and `id in [...]` read the record endpoint directly, one request
per record. The search answers it only when something else is filtered alongside it — a permission
scope, a segment, or a second filter.

**Free-text search** is answered on two collections, each on the one column its endpoint matches text
on:

| Collection | Searched on |
| --- | --- |
| `IntercomConversation` | `~` on `source.body` — the message that opened the conversation |
| `IntercomContact` | `~` on `email` — what an ops team types when they are looking for someone |

Intercom matches `~` **per word, not as a substring**: searching `fact` does not find `facture`, and
searching `acme` does not find `camille@acme.test`. `IntercomTicket` exposes no text column its
endpoint matches and refuses a search by name; `IntercomCompany` has no search endpoint at all.

### What is not filterable, and why

- **every column of a company but two.** There is no `/companies/search`: Intercom looks a company
  up by `name`, by `company_id`, by `tag_id` or by `segment_id`, one exact value at a time, and the
  first two are the ones that name a column of the collection. Everything else — the industry, the
  plan, the monthly spend — is refused by name. Filtering by tag or by segment belongs with the lot
  that adds those collections;
- **a contact's `company_id`, `company_count`, `avatar` and `session_count`** — the endpoint filters
  none of them. Reach the contacts of an account from the account instead, through its `contacts`
  relation, which `GET /companies/{id}/contacts` answers in one request — **and answers alone**. That
  endpoint returns the contacts of the account whole and narrows nothing, so a `company_id equals X`
  carrying anything else cannot be answered at all: there is no request that takes both halves.
  Which means the related list of an account **is refused as soon as a permission scope or a segment
  is defined on `IntercomContact`**, since that is what the agent intersects into the condition. The
  refusal names the condition it could not carry alongside the account. Resolving it properly would
  mean reading the account's contact ids first and handing `id IN [...]` plus the rest of the tree to
  `/contacts/search` — which that endpoint does answer, and which is not in this lot;
- **a set of ids, counted.** `id in [...]` reads one record per id (100 at a time on contacts), so
  counting a set means reading it, and past what a bulk read fetches the count is refused rather
  than answered with the number the truncation left. A collection that advertises an exact count does
  not answer 25 to a question about forty records;
- **the custom attributes of a contact or a company.** They are filtered as
  `custom_attributes.{name}`, by name — the ambiguity that keeps ticket attributes display-only does
  not arise here — but which operators Intercom answers on each data type has not been measured, and
  this package publishes no filter it has not seen work. They ship typed and display-only, and the
  probe is what turns that around;
- **the columns a ticket derives from its parts** — `closed_at`, `closed_by_name`, `last_reply_at`,
  `last_responder_name`, `last_responder_type`. They exist nowhere in Intercom; `/tickets/search`
  filters none of them and ignores a sort on them without a word;
- **the account of a ticket** — `company_id`, refused by the endpoint itself with `invalid_field`;
- **the state of a ticket** — the measured table carries no filter on a state id, so `state_id`,
  `previous_state_id` and the `state` relation are read and navigated rather than filtered. Whether
  the endpoint filters one at all is one of the probe's open questions;
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

### Through a relation

A relation is published filterable as soon as *any* column of its target is — the agent decides that,
not this datasource — so the interface offers `admin_assignee:name` the moment the relation exists.
What Intercom is really filtered on is the foreign key: the **target says which of its records
match**, over every record it holds rather than over a page, and the ids it names become the
condition the search carries.

That is exact, and it has four visible edges:

- **The target is read one record past what a group may hold, and no further.** Against a collection
  read whole that costs nothing — every record is in hand — but Contacts are a page of something
  far larger, and resolving `contact:email contains "@"` over a whole workspace to then refuse the
  fan-out it comes to would spend a full cursor walk on a filter that was never going to be
  answered. So the read is bounded, and the refusal says "more than fifteen" rather than a count it
  deliberately did not go and measure.
- Intercom takes no membership operator on these fields, so several matches become **one equality per
  match**, inside an `OR` — which counts against the fifteen conditions a group allows. A relation
  condition matching more records than that is refused by name rather than sent and answered with a
  400 naming neither the limit nor the filter that hit it. That `OR` is **inlined into a parent that
  aggregates the same way**, so it costs no level of nesting where it does not have to: the two
  levels Intercom allows are spent on the filter that was written, not on the expansion of a
  relation. Where inlining it would take the parent past fifteen conditions it stays nested, width
  being the scarcer of the two.
- A condition the target matched **no record** with names no row, and the DSL cannot say so: the
  search is skipped entirely rather than sent as a filter that would come back with everything.
- A relation whose foreign key the endpoint does not filter — the ticket `state`, a contact's
  `company` — is refused with a message saying which of the two it is: the relation is there to be
  read and navigated. Whether `/tickets/search` filters a state id or a contact id at all is one of
  the probe's open questions; the answer lands in the table, not in an assumption.

On the collections read whole the same condition costs nothing: they filter in memory, so the ids go
in as a plain membership and none of the DSL's limits apply.

A **many-to-many is published unfilterable** — `admins` and `teams` — and a condition written on one
anyway, in a scope or a segment, is refused before it reaches this datasource: the agent's own
validator answers a 400 naming the field and its type. Filter on a column of the collection next
door instead.

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

**The internal notes of the team are in the thread**, next to what the customer was told. That is
what a thread is on Intercom, and publishing half of it would be the more surprising answer — but it
is worth knowing before opening the collection to a role that should not read them.

The contact's name is denormalized onto the row by **one bulk read per page**, not one per row, and
only when the projection names it. A failure there costs that column, not the page. The e-mail is a
hop away, on the `contact` relation.

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

**The thread is published too, and it is free here.** The same `timeline` column a conversation
carries — who said what, when, and through which kind of event, internal notes and state changes
included — built from the parts the response already holds. No request per row and no cap: where a
conversation read from a listing carries no parts at all and leaves the column `nil` for *unknown*,
a ticket always carries them, so an empty list means an empty thread. Both reads ask Intercom for
`display_as=plaintext`: the bodies are HTML written by end customers, and rendering third-party
markup inside Forest is neither safe nor useful. The 500-part ceiling applies here as well, which is
the same truncation that can hide a closure date.

The attributes a workspace declares on its ticket types are introspected once at boot and published
as the **union** of every type's, keyed by name the way the payload is. Filtering one is a different
matter: Intercom filters an attribute by id (`ticket_attribute.{id}`), and the same name carries a
different id from one ticket type to the next — measured, `_default_title_` is `14162161` on one
type and `14162165` on another. A union column has no single id to translate to, so filtering on a
ticket attribute means one collection per ticket type — more collections in the interface, and a
schema that changes shape whenever the customer adds a type. Until that trade is worth paying for,
the attributes stay display-only and advertise no operator. The ids are kept per type so the day the
answer changes costs no second boot round trip.

## Contacts

The people who write in, users and leads alike. Cursor-paginated like conversations and tickets,
with two routes of its own and one thing no other collection has.

**Intercom sorts this one.** `POST /contacts/search` is the only endpoint of the whole API that
takes a `sort` and applies it, so these are the only sortable columns of the datasource: `name`,
`email`, `created_at`, `updated_at`, `signed_up_at`, `last_seen_at`, `last_contacted_at`,
`last_replied_at`. The set is deliberately narrower than the documentation implies — nothing has
been measured, and a sort Intercom refuses is a list view that fails rather than one that comes back
unordered. A sort on any other column, or on two columns at once, is reported in the log and the
rows come back in the API's order: Intercom takes a single `{ field, order }`, and honouring the
first clause of two would order the page by something nobody asked for.

An order is also what routes a plain list view through the search endpoint, the listing sorting
nothing: the read then carries the predicate matching everything that Tickets already send.

**Its date operators are narrower than the other two endpoints'** — measured, 25 August 2026:
`/contacts/search` refuses `>=`, `<=` and `!=` on a date where `/conversations/search` and
`/tickets/search` take them. Nothing is lost that an operator can see, a Date column publishing the
two bounds alone everywhere in this datasource, but it is why the operator table is per endpoint.

**A set of ids is read in one request** — `id IN [...]`, which this endpoint answers and no other
does — a hundred at a time, rather than one request per record. It is what makes a related list of
contacts affordable.

**`company_id equals X` reads `GET /companies/{id}/contacts`.** The search filters no company field,
so without that route the contacts of an account would be a refusal rather than a list. It is a bare
equality only: an `and` also carrying a permission scope names a narrower set than the account does,
and answering it with the account alone would serve contacts the scope excludes.

That is a limit worth knowing before scoping permissions, because it is not a slower route but no
route at all: the account endpoint returns its contacts whole and narrows nothing, and the search
filters no company field, so **a scope or a segment on this collection turns the related list of an
account into a refusal**. The message names the condition it could not carry alongside the account,
rather than telling the operator to open the account and read its contacts — which is what they were
doing. What would answer it is a read of the account's contact ids followed by `id IN [...]` plus the
rest of the tree on `/contacts/search`, which that endpoint takes; it is not in this lot.

One more thing the two routes do not agree on, and it is visible: the `company_id` column names **the
first** of the accounts a contact belongs to, and the `company` relation resolves that same first
one — while `company_id equals X` returns **every** contact of X. So an account's related list can
show a contact whose `company` points somewhere else. The column is the payload's reading; the filter
is the account endpoint's, and it is the more useful of the two.

**A merged contact reads as gone, not as an error.** Intercom drops it from the listing and from the
search, and the record lives on under the id it was merged into. A row pointing at the old id comes
back empty rather than failing the page.

The custom attributes a workspace declares on its contacts are introspected once at boot from
`GET /data_attributes?model=contact`, typed from `data_type`, and published display-only.

## Companies

The accounts contacts belong to, and the collection that behaves least like the others.

**Paginated by offset**, which is the tier above. **Looked up, not searched**: `name` and
`company_id` — the identifier the customer's own system gave the account, not Intercom's — are the
two filters it publishes, each an exact equality, and anything else is refused by name. A record is
read through `GET /companies/{id}`, and a set of ids one request each, capped at 25 with the
truncation logged.

`GET /companies/scroll` exists and is **deliberately rejected**: one open scroll per application,
expiring after a minute, cannot serve two operators looking at a list at the same time.

A contact carries its accounts as a list of ids and nothing else, so **projecting `company:name` on
a contact list costs one request per distinct account on the page**. Reading the account from the
contact's record page, or listing contacts from the account, both cost one.

Which is why that projection is the one relation of the datasource with a ceiling: past
[`MAX_RELATION_READS`](lib/forest_admin_datasource_intercom/collections/offset_collection.rb)
distinct accounts on a single read, it is **refused rather than resolved for part of the rows**. Every
page size a list view offers stays under it. A read that does not — an export, which batches a
thousand rows at a time, or a segment resolved whole — has to leave the column out. See
[Relations](#relations).

Custom attributes are introspected at boot the same way, from `GET /data_attributes?model=company`,
and published display-only for the same reason.

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

Constructing the datasource performs exactly **four** reads.

Three are of one kind: `GET /ticket_types` for the attribute columns of `IntercomTicket`, and
`GET /data_attributes?model=contact` and `?model=company` for those of `IntercomContact` and
`IntercomCompany`. A payload carries the values of the attributes that record happens to have been
given, never their definitions, which is why they cannot be discovered from the records.

The fourth is `GET /me`, and it reads no column: Intercom echoes in a response header the API
version it served, and it serves the workspace's own default when the pin is not honoured — whose
payloads are shaped differently from the ones this expects. That echo is the only place the
substitution shows, so it is checked while the agent starts and reported as a warning.

All four run on the boot connection — short timeouts, one quick retry — so a slow Intercom cannot
turn a Rails boot into minutes the operator sits through, and each degrades to a warning rather
than to a failed boot: a token missing a permission costs the columns it could not read, or the
version check, never the agent.

`api_writable` is read alongside each attribute and kept, although every column of this lot is
published read-only: it is what tells an attribute the API may write from one Intercom fills in
itself, and reading it again later would be a second boot-time round trip.

Everything else is read when a collection is listed, so an agent boots whatever Intercom is doing.

## What is not here yet

| Lot | What it brings |
| --- | --- |
| 3 | Writes and business actions on tickets and conversations: reply, close, snooze, reopen, assign, tag, convert |
| 4b | Writes on contacts and companies: create, update, archive, block, merge, attach and detach |
| 5 | Notes, tags, segments |
| 6 | Bounded group-by and the reporting export |

Two questions this lot leaves in the table rather than in an assumption, both for
`forest_admin_intercom_probe` to answer against the customer's workspace: whether `/tickets/search`
filters on `contact_ids`, and which operators `/contacts/search` answers on a custom attribute.

## Development

```bash
cd packages/forest_admin_datasource_intercom
BUNDLE_GEMFILE=Gemfile-test bundle install
BUNDLE_GEMFILE=Gemfile-test bundle exec rspec
bundle exec rubocop # from the repository root
```

`exe/forest_admin_intercom_probe` ships with the gem rather than living in the repository alone:
what it measures is the customer's workspace, and whoever runs it there has the gem installed and
not a clone of this repository. From a checkout it runs in place, `exe/forest_admin_intercom_probe`.

Specs stub the HTTP layer with WebMock. Every payload they feed in is **hand-written from the
OpenAPI 2.16 specification**, never captured from a workspace: a conversation body is personal data,
and a fixture is read by everyone who clones the repository.

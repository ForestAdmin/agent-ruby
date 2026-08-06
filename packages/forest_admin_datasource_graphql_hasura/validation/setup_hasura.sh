#!/usr/bin/env bash
# Tracks the tables and declares the relationships a Rails team would actually
# configure in Hasura (FK-based where a real FK exists, manual per polymorphic
# target elsewhere — the type condition cannot be expressed).
set -euo pipefail

HASURA_URL="${HASURA_URL:-http://localhost:58080}"
ADMIN_SECRET="${ADMIN_SECRET:-hasura-validation-secret}"

metadata() {
  local body="$1"
  local response
  response=$(curl -sS -X POST "$HASURA_URL/v1/metadata" \
    -H "x-hasura-admin-secret: $ADMIN_SECRET" \
    -H 'Content-Type: application/json' \
    -d "$body")
  if echo "$response" | grep -q '"error"'; then
    echo "FAILED: $body" >&2
    echo "$response" >&2
    exit 1
  fi
}

for table in memberships transfers cards bank_accounts comments attachments card_memberships transfer_stats; do
  metadata "{\"type\":\"pg_track_table\",\"args\":{\"source\":\"default\",\"table\":{\"schema\":\"public\",\"name\":\"$table\"}}}"
done

object_rel_fk() { # table name fk_column
  metadata "{\"type\":\"pg_create_object_relationship\",\"args\":{\"source\":\"default\",\"table\":{\"schema\":\"public\",\"name\":\"$1\"},\"name\":\"$2\",\"using\":{\"foreign_key_constraint_on\":\"$3\"}}}"
}

object_rel_manual() { # table name remote_table local_col remote_col
  metadata "{\"type\":\"pg_create_object_relationship\",\"args\":{\"source\":\"default\",\"table\":{\"schema\":\"public\",\"name\":\"$1\"},\"name\":\"$2\",\"using\":{\"manual_configuration\":{\"remote_table\":{\"schema\":\"public\",\"name\":\"$3\"},\"column_mapping\":{\"$4\":\"$5\"}}}}}"
}

array_rel_fk() { # table name remote_table fk_column
  metadata "{\"type\":\"pg_create_array_relationship\",\"args\":{\"source\":\"default\",\"table\":{\"schema\":\"public\",\"name\":\"$1\"},\"name\":\"$2\",\"using\":{\"foreign_key_constraint_on\":{\"table\":{\"schema\":\"public\",\"name\":\"$3\"},\"column\":\"$4\"}}}}"
}

array_rel_manual() { # table name remote_table local_col remote_col
  metadata "{\"type\":\"pg_create_array_relationship\",\"args\":{\"source\":\"default\",\"table\":{\"schema\":\"public\",\"name\":\"$1\"},\"name\":\"$2\",\"using\":{\"manual_configuration\":{\"remote_table\":{\"schema\":\"public\",\"name\":\"$3\"},\"column_mapping\":{\"$4\":\"$5\"}}}}}"
}

# transfers.beneficiary: a real FK sitting next to the `beneficiary_type` enum —
# must stay a plain ManyToOne, never be absorbed into a polymorphic relation.
object_rel_fk transfers beneficiary beneficiary_id
array_rel_fk memberships transfers transfers beneficiary_id

# comments: real FK + one manual relationship per polymorphic target
object_rel_fk comments membership membership_id
object_rel_manual comments transfer transfers commentable_id id
object_rel_manual comments card cards commentable_id id

# attachments: two polymorphic belongs_to (attachable multi-target, author single-target)
object_rel_manual attachments transfer transfers attachable_id id
object_rel_manual attachments bank_account bank_accounts attachable_id id
object_rel_manual attachments membership memberships author_id id

# reverse sides
array_rel_fk memberships comments comments membership_id
array_rel_manual memberships attachments attachments id author_id
array_rel_manual transfers comments comments id commentable_id
array_rel_manual transfers attachments attachments id attachable_id
array_rel_manual cards comments comments id commentable_id
array_rel_manual bank_accounts attachments attachments id attachable_id

echo 'Hasura metadata configured.'

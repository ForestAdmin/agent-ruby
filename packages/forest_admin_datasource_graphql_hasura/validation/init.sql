-- Rails-like banking schema covering the supported polymorphism scenarios:
--   * comments.commentable  -> Transfer | Card          (multi-target, bigint PKs)
--   * attachments.attachable -> Transfer | Banking::BankAccount (namespaced model)
--   * attachments.author     -> Membership              (single-target polymorphic)
--   * attachments has a uuid primary key
--   * cards uses STI (type column, one legacy row stores the subclass name)
--   * card_memberships is a join table with a composite primary key
--   * dangling and null polymorphic references

CREATE TABLE memberships (
  id bigserial PRIMARY KEY,
  full_name text NOT NULL
);

CREATE TYPE card_status AS ENUM ('active', 'blocked');

CREATE TABLE transfers (
  id bigserial PRIMARY KEY,
  amount_cents bigint NOT NULL,
  status varchar,
  tags text[],
  -- The false-positive trap: a business enum column named like a polymorphic
  -- discriminator, sitting next to a real foreign key.
  beneficiary_type varchar,
  beneficiary_id bigint REFERENCES memberships(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE cards (
  id bigserial PRIMARY KEY,
  last4 varchar,
  status card_status NOT NULL DEFAULT 'active',
  type varchar NOT NULL DEFAULT 'Card',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE bank_accounts (
  id bigserial PRIMARY KEY,
  iban text NOT NULL
);

CREATE TABLE comments (
  id bigserial PRIMARY KEY,
  body text,
  metadata jsonb,
  commentable_type varchar,
  commentable_id bigint,
  membership_id bigint REFERENCES memberships(id),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  file_name text NOT NULL,
  attachable_type varchar NOT NULL,
  attachable_id bigint NOT NULL,
  author_type varchar,
  author_id bigint
);

CREATE TABLE card_memberships (
  card_id bigint NOT NULL REFERENCES cards(id),
  membership_id bigint NOT NULL REFERENCES memberships(id),
  PRIMARY KEY (card_id, membership_id)
);

-- A view without a primary key: must be skipped, not exposed broken.
CREATE VIEW transfer_stats AS
  SELECT beneficiary_id, sum(amount_cents) AS total_cents FROM transfers GROUP BY beneficiary_id;

INSERT INTO memberships (full_name) VALUES ('Jane Doe'), ('John Smith');
INSERT INTO transfers (amount_cents, status, tags, beneficiary_type, beneficiary_id) VALUES
  (125000, 'completed', ARRAY['urgent', 'sepa'], 'internal', 1),
  (9900, 'pending', NULL, 'external', 2);
INSERT INTO cards (last4, status, type) VALUES ('4242', 'active', 'Card'), ('9999', 'blocked', 'FlashCard');
INSERT INTO bank_accounts (iban) VALUES ('FR7630006000011234567890189');

-- The faux-join trap: Transfer#1 and Card#1 both have comments.
INSERT INTO comments (body, metadata, commentable_type, commentable_id, membership_id) VALUES
  ('on transfer 1', '{"source": "api"}', 'Transfer', 1, 1),
  ('on card 1', NULL, 'Card', 1, 1),
  ('second on transfer 1', NULL, 'Transfer', 1, 2),
  ('legacy sti row', NULL, 'FlashCard', 2, 1),
  ('dangling target', NULL, 'Transfer', 999, 2),
  ('no target', NULL, NULL, NULL, 1),
  -- Empty string vs NULL: "is present" and "is blank" must not overlap.
  ('', NULL, 'Transfer', 2, 1),
  (NULL, NULL, 'Transfer', 2, 1),
  -- Literal wildcards: a "contains 100%" search must not match these both.
  ('discount 100% applied', NULL, 'Transfer', 2, 1),
  ('discount 1000 applied', NULL, 'Transfer', 2, 1),
  -- NULL foreign key: grouped charts must give it the bucket SQL grouping would.
  ('orphan comment', NULL, 'Card', 1, NULL);

INSERT INTO attachments (file_name, attachable_type, attachable_id, author_type, author_id) VALUES
  ('invoice.pdf', 'Transfer', 1, 'Membership', 1),
  ('rib.pdf', 'Banking::BankAccount', 1, 'Membership', 2);

INSERT INTO card_memberships (card_id, membership_id) VALUES (1, 1), (1, 2);

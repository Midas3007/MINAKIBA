-- MINAKIBA database, first migration. Plain SQL, applied in order; schema_migrations records what ran.
-- Every table carries `network` ('base' or 'base-sepolia') so testnet and mainnet never mix.

CREATE TABLE IF NOT EXISTS schema_migrations (
  version     text PRIMARY KEY,
  applied_at  timestamptz NOT NULL DEFAULT now()
);

-- One row per network: which vault the jobs work on, and how the keeper last went.
CREATE TABLE vault_config (
  network               text PRIMARY KEY,
  chain_id              integer NOT NULL,
  vault_address         text,
  usdc_address          text NOT NULL,
  treasury_address      text NOT NULL,
  keeper_address        text,
  start_block           bigint NOT NULL DEFAULT 0,       -- where chain reading starts (vault deploy block)
  season_start          date,
  last_run_at           timestamptz,
  last_result           text,
  last_settle_day       date,
  settle_waiting_since  timestamptz,
  settle_waiting_reason text,
  updated_at            timestamptz NOT NULL DEFAULT now()
);

-- Every value report and settlement, read back from the chain.
CREATE TABLE vault_history (
  network     text NOT NULL,
  kind        text NOT NULL CHECK (kind IN ('report', 'settle')),
  block       bigint NOT NULL,
  log_index   integer NOT NULL,
  tx_hash     text NOT NULL,
  at          timestamptz NOT NULL,
  nav         numeric(30, 6) NOT NULL,              -- USD
  supply      numeric(40, 18) NOT NULL,             -- shares
  price       numeric(30, 6) NOT NULL,              -- USD per share
  naira_rate  numeric(20, 6),                       -- NGN per $1 (settlements)
  deposits    numeric(30, 6),
  payouts     numeric(30, 6),
  nav_after   numeric(30, 6),
  supply_after numeric(40, 18),
  PRIMARY KEY (network, tx_hash, log_index)
);
CREATE INDEX vault_history_at ON vault_history (network, at);

-- Member-facing vault events (deposits, redemptions with fees, claims, role changes): the fee ledger,
-- leaderboard and alerts read from here. `data` holds the decoded event fields.
CREATE TABLE vault_events (
  network     text NOT NULL,
  block       bigint NOT NULL,
  log_index   integer NOT NULL,
  tx_hash     text NOT NULL,
  at          timestamptz NOT NULL,
  name        text NOT NULL,
  member      text,
  data        jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (network, tx_hash, log_index)
);
CREATE INDEX vault_events_member ON vault_events (network, member, block);
CREATE INDEX vault_events_name ON vault_events (network, name, block);

-- Every USDC / cNGN transfer in or out of the treasury wallet, read from the chain. Never deleted.
CREATE TABLE pool_tx (
  network      text NOT NULL,
  block        bigint NOT NULL,
  tx_index     integer NOT NULL,
  log_index    integer NOT NULL,
  tx_hash      text NOT NULL,
  at           timestamptz NOT NULL,
  token        text NOT NULL CHECK (token IN ('USDC', 'cNGN')),
  direction    text NOT NULL CHECK (direction IN ('in', 'out')),
  amount       numeric(38, 6) NOT NULL,
  counterparty text NOT NULL,
  PRIMARY KEY (network, tx_hash, log_index)
);
CREATE INDEX pool_tx_order ON pool_tx (network, block, tx_index, log_index);

-- Reading cursors, one per stream ('pool', 'vault').
CREATE TABLE pool_sync (
  network      text NOT NULL,
  stream       text NOT NULL,
  cursor_block bigint NOT NULL DEFAULT 0,
  stale        boolean NOT NULL DEFAULT false,
  last_error   text,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (network, stream)
);

-- Addresses whose transfers are not trades (the vault, top-ups, withdrawals).
CREATE TABLE excluded_addresses (
  network  text NOT NULL,
  address  text NOT NULL,             -- lower case
  label    text NOT NULL,
  PRIMARY KEY (network, address)
);

-- Trades paired from treasury USDC transfers: each leg is numbered by how many sales (USDC in) came before it;
-- a trade is its buys (USDC out) plus the one sale that closes it. profit = sale - buys.
CREATE VIEW trade_legs AS
SELECT p.*,
       COALESCE(SUM(CASE WHEN p.direction = 'in' THEN 1 ELSE 0 END)
         OVER (PARTITION BY p.network ORDER BY p.block, p.tx_index, p.log_index
               ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING), 0) AS trade_no
FROM pool_tx p
WHERE p.token = 'USDC'
  AND NOT EXISTS (SELECT 1 FROM excluded_addresses e WHERE e.network = p.network AND e.address = lower(p.counterparty));

CREATE VIEW trades AS
SELECT network,
       trade_no,
       MIN(at)                                                     AS opened_at,
       MAX(at) FILTER (WHERE direction = 'in')                     AS closed_at,
       SUM(amount) FILTER (WHERE direction = 'out')                AS bought,
       SUM(amount) FILTER (WHERE direction = 'in')                 AS sold,
       COALESCE(SUM(amount) FILTER (WHERE direction = 'in'), 0)
         - COALESCE(SUM(amount) FILTER (WHERE direction = 'out'), 0) AS profit,
       COUNT(*) FILTER (WHERE direction = 'in') = 1                AS closed,
       array_agg(tx_hash ORDER BY block, tx_index, log_index)      AS txs
FROM trade_legs
GROUP BY network, trade_no;

-- The running-costs pot (not part of the share price).
CREATE TABLE treasury_config (
  network                 text PRIMARY KEY,
  carve_bps               integer NOT NULL DEFAULT 1000,     -- 10% of each day's trading profit
  target_days             integer NOT NULL DEFAULT 60,       -- visualiser: fill against 60 days of costs
  hosting_usd_per_day     numeric(12, 6) NOT NULL DEFAULT 0,
  withdraw_min            numeric(12, 6) NOT NULL DEFAULT 5,
  withdraw_max            numeric(12, 6) NOT NULL DEFAULT 10,
  withdraw_every_days     integer NOT NULL DEFAULT 30,
  updated_at              timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE treasury_days (
  network         text NOT NULL,
  day             date NOT NULL,                 -- settlement day (UTC)
  trading_profit  numeric(20, 6) NOT NULL DEFAULT 0,
  carve           numeric(20, 6) NOT NULL DEFAULT 0,
  gas_usd         numeric(20, 6) NOT NULL DEFAULT 0,
  hosting_usd     numeric(20, 6) NOT NULL DEFAULT 0,
  shortfall_usd   numeric(20, 6) NOT NULL DEFAULT 0,   -- paid by the shares' value when the pot was short
  PRIMARY KEY (network, day)
);

-- Every movement of the pot. amount > 0 adds to the pot, < 0 takes from it.
CREATE TABLE treasury_entries (
  id             bigserial PRIMARY KEY,
  network        text NOT NULL,
  at             timestamptz NOT NULL DEFAULT now(),
  kind           text NOT NULL CHECK (kind IN ('carve', 'gas', 'keeper_gas', 'hosting', 'withdrawal', 'shortfall', 'adjust')),
  amount         numeric(20, 6) NOT NULL,
  status         text NOT NULL DEFAULT 'done' CHECK (status IN ('pending', 'done', 'failed', 'cancelled')),
  to_address     text,
  tx_hash        text,
  note           text,
  requested_by   text
);
CREATE INDEX treasury_entries_at ON treasury_entries (network, at);
CREATE VIEW treasury_pot AS
SELECT network, COALESCE(SUM(amount) FILTER (WHERE status IN ('done', 'pending')), 0) AS balance
FROM treasury_entries GROUP BY network;

-- Switches Kiyoshi reads (changed from the admin page or Telegram; none of them moves money).
CREATE TABLE bot_settings (
  network          text PRIMARY KEY,
  smart_sizing     boolean NOT NULL DEFAULT true,
  skip_waits       boolean NOT NULL DEFAULT false,
  tight_first_leg  boolean NOT NULL DEFAULT true,
  updated_at       timestamptz NOT NULL DEFAULT now(),
  updated_by       text
);

-- Heartbeats signed by the treasury wallet. nonce is unique so a replayed message is refused.
CREATE TABLE bot_heartbeat (
  id          bigserial PRIMARY KEY,
  network     text NOT NULL,
  at          timestamptz NOT NULL DEFAULT now(),
  signed_at   timestamptz NOT NULL,
  nonce       text NOT NULL UNIQUE,
  mid_trade   boolean NOT NULL DEFAULT false,
  holding     boolean NOT NULL DEFAULT false,
  live        boolean NOT NULL DEFAULT false,
  gas_eth     numeric(20, 9),
  cycle_ok    boolean NOT NULL DEFAULT true,
  last_error  text,
  payload     jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX bot_heartbeat_at ON bot_heartbeat (network, at DESC);

-- Telegram link and alert memory (each alert once, then every 6 hours, then "OK again").
CREATE TABLE alert_config (
  id          smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  chat_id     bigint,
  linked_at   timestamptz,
  enabled     boolean NOT NULL DEFAULT true
);
CREATE TABLE alert_state (
  key           text PRIMARY KEY,
  active        boolean NOT NULL DEFAULT false,
  first_at      timestamptz,
  last_sent_at  timestamptz,
  detail        text
);

-- One-time nonces for wallet-signed admin logins and "Settle now".
CREATE TABLE admin_nonces (
  nonce       text PRIMARY KEY,
  purpose     text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  used_at     timestamptz
);

-- Finished seasons with their summary and leaderboard.
CREATE TABLE seasons (
  id           serial PRIMARY KEY,
  network      text NOT NULL,
  name         text NOT NULL,
  started_at   timestamptz NOT NULL,
  ended_at     timestamptz,
  summary      jsonb NOT NULL DEFAULT '{}',
  leaderboard  jsonb NOT NULL DEFAULT '[]'
);

INSERT INTO schema_migrations (version) VALUES ('001_init');

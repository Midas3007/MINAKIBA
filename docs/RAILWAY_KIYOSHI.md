# Running Kiyoshi (Base) on Railway

Kiyoshi on Base is a long-running process (`npm run base-desk`) that keeps its trade log on disk. Railway runs it as
one always-on service with a volume. The fund's site, API and scheduled jobs stay on Vercel and Neon.

**Rule that matters most:** only one live copy of the bot may run per wallet. Keep replicas at 1, and keep any old
host (Render, a laptop) stopped before you set `LIVE=1` on Railway.

## 1. The code
The bot lives in this repo at `kiyoshi/` (copied from Mel's repo; see `kiyoshi/UPSTREAM.md`). Node 22 is pinned and
`tsx` is a normal dependency, so Railway can build it as is.

## 2. Create the service
1. railway.com → New Project → Deploy from GitHub repo → `Midas3007/MINAKIBA` (authorise the Railway GitHub app for it).
2. Service → Settings:
   * **Root directory:** `/kiyoshi`
   * **Branch:** the branch you deploy from (`main` once this work is merged)
   * **Start command:** `npm run base-desk`
   * **Replicas:** 1
   * **Restart policy:** On failure
   * **Healthcheck path:** `/health`
   * **Watch paths:** `/kiyoshi/**` (so changes to the site or contracts don't restart the bot)
3. Service → right-click → **Attach volume**, mount path `/data` (1 GB is plenty).

## 3. Variables (Service → Variables)
| Variable | Value |
|---|---|
| `AGENT_PRIVATE_KEY` | the treasury wallet's key. Add it as a **sealed** variable. Paste it only into Railway, never into chat, a file or a commit. |
| `BASE_RPC` | your own Base RPC URL (see *Getting an RPC* below). Without it the bot uses the public `https://mainnet.base.org`, which is rate limited. Treat the URL as a secret: it contains your key. |
| `LIVE` | `0` first (dry run), `1` once the checks below pass |
| `DATA_DIR` | `/data` |
| `MAX_TRADE_USD` | e.g. `50`. The thin pool loses margin above about $600 (Celo lesson); start small. |
| `MIN_EDGE_USD` | `0.01` |
| `INTERVAL_SEC` / `CHASE_SEC` | `60` / `10` |
| `SLIPPAGE_BPS` | `30` |
| `MAX_FLATTEN_LOSS_BPS` / `MAX_HOLD_MIN` | `50` / `30` (second-leg guard) |
| `MIN_GAS_ETH` | `0.0002` |
| `STARTUP_DELAY_SEC` | `60` (lets an old copy stop before trading) |

Railway sets `PORT` itself, so the bot serves `/health`, `/status`, `/trades` and `/pnl`.
Do not generate a public domain unless someone needs `/status` from outside. The fund reads trades from the chain,
not from the bot.

## 4. First run (dry)
1. Deploy with `LIVE=0`. In Deploy Logs, look for
   `Kiyoshi Base DRY RUN | cNGN/USDC | wallet 0xcbf9…512c`. The wallet must match the treasury in
   `config/fund.config.js`. If it doesn't, stop: the wrong key is loaded.
2. Watch a few cycles: quotes from Textile and Uniswap, no errors.

## 5. Go live
1. Fund the treasury: USDC for trading plus a little ETH for gas (it currently holds almost none).
2. Set `LIVE=1` (Railway redeploys). Logs should show `LIVE` and, after the 60 s wait, real cycles.
3. Check the first trades on basescan.org/address/0xcbf9f04c80451d043062daf27e36e55bbbe8512c.

## 6. Day to day
* **Stop trading at once:** set `LIVE=0`, or Service → Settings → remove the active deployment. Either stops new
  trades. Funds stay in the wallet.
* **Redeploys:** with a volume attached, Railway stops the old copy before starting the new one, so two copies never
  trade at once. The bot finishes its current cycle on SIGTERM.
* **Logs** are in the Railway dashboard; the trade log is `/data/base-trades.jsonl` on the volume.

## Still to add for the fund (a small patch on Mel's side)
The fund needs three things the Base desk doesn't do yet: a signed heartbeat POST to the fund API, reading the switches
(smart sizing, skip waits, tight first leg) from the fund's settings endpoint, and checking the pending pot withdrawal.
These come with the fund's API work; they'll add one variable, `FUND_API_URL`.

## Getting an RPC (free)
The bot makes roughly 15 to 25 calls a minute (quotes at three sizes in both directions, balances, gas), about 1 million
a month. The fund's jobs (pool sync every 2 minutes, keeper hourly, alerts) add less than that. Every major provider's
free plan covers this.

1. Sign up at one provider, e.g. **Alchemy** (alchemy.com) or **QuickNode** (quicknode.com); **dRPC** (drpc.org) and
   **Chainstack** also have free plans.
2. Create an app / endpoint, network **Base Mainnet**. Make a second one on **Base Sepolia** for the fund's testnet week.
3. Copy the HTTPS URL. It looks like `https://base-mainnet.g.alchemy.com/v2/<key>`.
4. Put it in Railway as `BASE_RPC` (sealed). Use a **separate** key (or a second provider) for the fund on Vercel
   (`BASE_RPC_URL`), so if one is throttled the other keeps working.
5. Check usage on the provider's dashboard after the first day.

# MINAKIBA build plan

Two tracks, from `MINAKIBA_FUND_BUILD.md` and `MINAKIBA_OPENING_FILM.md`.

## Fund (brief section 13 order)
1. Confirm facts, `config/fund.config.js` with sources. **Done.**
2. `contracts/`: Foundry. **Contract + 23 tests done; deploy waits on test ETH.** FundVault.sol ported from Celo with the 5.2 changes; full test list from 5.3.
   Base Sepolia with a mock USDC, a week of test settlements, then mainnet with the Safe as owner, verify on Basescan.
3. `db/migrations/`: numbered SQL for Neon (`main` + `dev` branch). **Done.**
4. Vercel project, env vars (**project and env vars done**), `vercel.json` (headers, CSP, cron). Check the first push really deploys.
5. `api/`: keeper, pool-sync, alerts + Telegram, bot interface (heartbeat, settings, pot withdrawal).
6. `web/`: dashboard, account, admin. viem bundled into `web/vendor/`.
7. Security pass, phone test with a real wallet on testnet.
8. Go-live checklist.

## Differences found against the brief
* Kiyoshi on Base trades a **Uniswap v4** pool (0.15%, tick spacing 30), not v3. Keeper, pool sync and the spread
  monitor will read v4 (PoolManager / StateView), and bounded approvals go to Permit2 + Universal Router.
* Kiyoshi's Base desk has no heartbeat, settings GET or pot-withdrawal GET yet. These need a small patch on Mel's side
  (I can write it as a separate file for Mel to drop in).
* Textile is priced by RFQ preview in Kiyoshi; no public ticker id is used.

## Film
`film/opening.html`, `film/render.cjs`, `film/score.py`, then both cuts and posters. Independent of the fund; can run
in parallel. The naira rate on screen is left out until the fund has a real one.

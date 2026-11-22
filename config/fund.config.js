// MINAKIBA: the one place every address and fund setting lives.
// The site, the API and the deploy scripts all read this file. Never guess an address:
// each entry says where it came from. `null` = still to confirm with the manager.
//
// Source "kiyoshi" = github.com/MELcodes99/kiyoshi, src/base/config.ts at commit 9200aff (16 Nov 2026).

export const CHAIN = {
  mainnet: { id: 8453, name: 'Base', explorer: 'https://basescan.org' },
  testnet: { id: 84532, name: 'Base Sepolia', explorer: 'https://sepolia.basescan.org' },
}

export const TOKENS = {
  // kiyoshi: BASE_TOKENS.USDC. Kiyoshi holds USDC (its only stablecoin on Base).
  USDC: { address: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913', decimals: 6 },
  // kiyoshi: BASE_TOKENS.cNGN
  cNGN: { address: '0x46C85152bFe9f96829aA94755D9f915F9B10EF5F', decimals: 6 },
}

// NOTE: the build brief says Uniswap v3. Kiyoshi on Base actually trades a Uniswap **v4** pool.
export const UNISWAP = {
  version: 4,
  // kiyoshi: scripts/base-v4-arb.ts (POOL_MANAGER)
  poolManager: '0x498581fF718922c3f8e6A244956aF099B2652b2b',
  // kiyoshi: V4.QUOTER
  quoter: '0x0d5e0f971ed27fbff6c2837bf31316121532048d',
  // kiyoshi: V4.ROUTER (Universal Router)
  router: '0x6ff5693b99212da76ad316178a184ab56d299b43',
  // kiyoshi: V4.PERMIT2
  permit2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
  // To confirm: v4 StateView on Base (needed to read the pool price for the naira rate).
  stateView: null,
  // kiyoshi: CNGN_POOL. cNGN/USDC, 0.15% fee, tick spacing 30, no hook.
  cngnPool: {
    id: '0x84fa97768196067f0e5aa157709039a3897e219cba3002d9ad38bf44e300fe93',
    fee: 1500,
    tickSpacing: 30,
    hooks: '0x0000000000000000000000000000000000000000',
  },
}

export const TEXTILE = {
  // kiyoshi: BASE_TEXTILE_REACTOR (from docs.textilecredit.com/protocol/address-book)
  reactor: '0xEb5A29F869FF084B3Fce18d3487a38A56feDC59E',
  // kiyoshi: src/config.ts TEXTILE_API. Kiyoshi prices with POST /v2/rfq/preview (chainId 8453).
  api: 'https://api.textilecredit.com',
  // To confirm: a public ticker id for cNGN. If there is none, the fund rate uses an RFQ preview mid.
  cngnTicker: null,
}

export const WALLETS = {
  treasury: null,     // Kiyoshi's Base wallet (derived from its key; not in the repo)
  owner: null,        // Safe multisig or hardware wallet. Must NOT be the bot wallet.
  manager: null,      // manager's personal wallet
  feeRecipient: null,
  keeper: null,       // new wallet, holds gas only; key lives in Vercel env
}

export const VAULT = {
  mainnet: null,      // filled after deploy
  testnet: null,
}

export const FUND = {
  feeBps: null,                 // Celo fund runs 1500 (15%); hard cap 2000
  feeCapBps: 2000,
  maxNavChangeBps: 2500,        // brief 5.2
  changeDelaySec: 48 * 3600,    // brief 5.1
  queueLimit: 100,
  depositCapUsd: null,
  minDepositUsd: null,
  settleUtc: '20:07',           // 21:07 Lagos time
  potCarveBps: 1000,            // 10% of each day's trading profit
}

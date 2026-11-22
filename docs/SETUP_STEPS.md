# MINAKIBA: what you need to set up yourself

These are the things I can't do from here, because each one needs you to sign in, prove you're human, or hold a
secret that must never pass through chat. Do them in order. Each step says what it unlocks, so you can stop after any
step and pick up later.

**One rule for every step:** a *secret* (a key, token, password or private RPC link) goes only where the step says
(usually Vercel or Railway). Never paste one into this chat, an email, WhatsApp or a document. If one leaks by
accident, tell me and we'll replace it.

---

## Step 1. Turn on two-factor login (10 minutes)

*Unlocks: nothing new. It protects everything else.* If someone gets into one of these accounts, they could change
the fund's code or settings.

Do this for each account below. You'll need an authenticator app on your phone: Google Authenticator, Microsoft
Authenticator or 1Password all work.

1. **GitHub:** github.com → your picture (top right) → **Settings** → **Password and authentication** →
   **Enable two-factor authentication** → follow the screens (scan the QR code with the app, type the 6-digit code).
   **Save the recovery codes** somewhere safe and offline (printed, or in a password manager).
2. **Vercel:** vercel.com → your picture → **Account Settings** → **Authentication** → **Two-Factor Authentication**
   → turn it on the same way.
3. **Neon:** console.neon.tech → your picture → **Account settings** → **Security** → set up two-factor.
4. **Telegram:** in the app, **Settings** → **Privacy and Security** → **Two-Step Verification** → set a password
   (and a recovery email).
5. **Railway** (when you use it): railway.com → **Account Settings** → **Security** → two-factor.

---

## Step 2. Get your own free RPC links (10 minutes)

*Unlocks: everything that reads or writes the blockchain (the keeper, trade history, the site's live numbers).*

An RPC link is the address the fund's computers use to talk to Base. The free public one gets overloaded, so you
need your own. It's free.

1. Go to **alchemy.com** and click **Sign up**. Signing up with Google is quickest.
2. When it asks what you're building, pick anything (e.g. "DeFi"). Skip any paid plan offers; the **Free** plan is
   enough.
3. Create an app: click **Create new app** (or **+ New app**).
   * Name: `MINAKIBA`
   * Chain: **Base**
   * Networks: tick **Base Mainnet** and **Base Sepolia** (Sepolia is the free test network).
4. Open the app. Find the **Endpoints** / **Networks** section. For each network there's an **HTTPS** link that looks
   like `https://base-mainnet.g.alchemy.com/v2/AbCdEf...`. The part after `/v2/` is your key, so this link is a secret.
5. Put both links into Vercel (Vercel saves them; you don't need to keep a copy):
   1. Go to **vercel.com** → open the team **midart** → open the project **minakiba**.
   2. Click **Settings** (top menu) → **Environment Variables** (left menu).
   3. Add the first one:
      * **Key:** `BASE_RPC_URL`
      * **Value:** paste the **Base Mainnet** HTTPS link
      * Switch **Sensitive** on.
      * **Environments:** tick **Production** and **Preview**.
      * Click **Save**.
   4. Add the second one the same way, with **Key** `BASE_SEPOLIA_RPC_URL` and the **Base Sepolia** link as the
      **Value**.
6. **For Kiyoshi on Railway**, make a second Alchemy app (e.g. `Kiyoshi`, Base Mainnet only) and use *its* link as
   `BASE_RPC` in Railway. Separate links mean that if one is busy, the other keeps working. (Railway steps:
   `docs/RAILWAY_KIYOSHI.md`.)

Tell me "RPC done" when it's saved. You don't need to tell me the link.

---

## Step 3. Free test ETH for the test fund (10 minutes)

*Unlocks: deploying the test vault on Base Sepolia and the week of test settlements.*

Test ETH is free play money on the test network. It has no value. I made a test wallet that deploys the test vault
and runs the test keeper:

**Test keeper wallet:** `0xC0232463A666Fa2fF42E9c43f8f598520EED92f9`

1. Open a Base Sepolia faucet (a site that gives out test ETH). Either works:
   * **Coinbase faucet:** portal.cdp.coinbase.com → sign in with a Coinbase account → **Faucets** → network
     **Base Sepolia**, token **ETH**.
   * **Alchemy faucet:** alchemy.com/faucets/base-sepolia (you're already signed in from Step 2).
2. Paste the test keeper address above and click **Send** / **Claim**.
3. Repeat (faucets give small amounts; some let you claim once a day) until it has about **0.01 test ETH**. You can
   check at sepolia.basescan.org: paste the address in the search box.
4. Also claim some test ETH for **your own wallet** (`0xf95E…3113`) the same way. You'll need it to try the admin
   page (pause, approve wallets) on the test fund. Your hardware wallet works on Base Sepolia in MetaMask or Rabby:
   add the network "Base Sepolia" in the wallet if it isn't listed.

Some faucets ask that the address holds a little real ETH on mainnet first; if one refuses, try the other.

Tell me "test ETH sent" when it has arrived. I'll deploy the test vault, give the other test wallets their share,
and start the test week.

---

## Step 4. A Basescan key, so anyone can read the fund's code (5 minutes)

*Unlocks: publishing ("verifying") the vault's source code on Basescan, so members can check what the contract does.*

1. Go to **etherscan.io/register**, create an account, and confirm your email. One Etherscan account covers Base too.
2. Sign in → click your username (top right) → **API Keys** → **+ Add** → name it `MINAKIBA` → **Create**.
3. Leave the page open. When I deploy, **a secure form will pop up in this app** asking for the key for
   `api.etherscan.io`. Paste it there, not in the chat. The form stores it so only the network layer can use it; I
   never see it.

---

## Step 5. The Telegram alert bot (5 minutes)

*Unlocks: alerts on your phone (bot silent, price drop, a queued vault change, daily summary).*

1. In Telegram, search for **@BotFather**. It's the official one, with a blue tick.
2. Send `/newbot`.
3. Send a display name: `MINAKIBA Alerts`.
4. Send a username. It must end in `bot` and nobody else can have it, e.g. `minakiba_alerts_bot`. If it's taken,
   try another.
5. BotFather replies with a **token** that looks like `1234567890:AAH...`. This is a secret: anyone with it controls
   the bot.
6. Add it to Vercel (same place as Step 2): **Key** `TELEGRAM_BOT_TOKEN`, paste the token as the **Value**, switch
   **Sensitive** on, tick **Production** and **Preview**, then click **Save**.
7. Don't message the bot yet. Once the alerts are built I'll tell you to open it and send `/start`. The first private
   `/start` links the bot to you, and after that it answers only you.

---

## Step 6. Answer one question

Your **$50 deposit cap**: is it

* **per member** (each wallet can put in up to $50; the fund grows with members), or
* **for the whole fund** (all members together, $50 in total)?

The contract supports both. I've assumed **per member** until you say otherwise. You can change either limit later
from the admin page, instantly; limits are not one of the 48-hour changes.

---

## Later (I'll tell you when)

These come at the end. You don't need to do anything yet.

* **Connect GitHub to Vercel**, so the site updates itself when code changes. I'll ask once the site is ready to go
  public. (Vercel → project → Settings → Git → Connect, then approve Vercel's GitHub app for `Midas3007/MINAKIBA`.)
* **Make the real keeper wallet** for mainnet. You'll create a fresh wallet in MetaMask or Rabby (not your hardware
  wallet, and not Kiyoshi's), put its private key straight into Vercel, and send it a little real ETH for gas. I'll
  give exact clicks then. It never holds fund money, only gas.
* **Kiyoshi on Railway:** steps in `docs/RAILWAY_KIYOSHI.md`. Do it when Mel is ready to go live.
* **Opening shares and allow-listing members:** buttons on the admin page, signed with your hardware wallet.

---

## What's already done (for reference)

| Thing | Where | Status |
|---|---|---|
| Vault contract + 23 tests (all passing) | `contracts/` | Done; not deployed yet |
| Database | Neon project **minakiba** (branches `main` and `dev`) | Created, tables in place |
| Hosting | Vercel project **minakiba** (team midart) | Created, settings saved, nothing published yet |
| Kiyoshi's code | `kiyoshi/` in the repo | Copied, tests passing |
| Opening film | `film/out/` | Done |

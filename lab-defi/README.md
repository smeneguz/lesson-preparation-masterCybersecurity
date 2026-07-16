# Lab — DeFi · A constant-product AMM (`x · y = k`)

Build the core of a Uniswap-style liquidity pool and watch the constant-product
curve in action: **pricing, slippage, and why one big swap moves the spot price**
(the hook into oracle / flash-loan attacks).

Companion to the slides *"The constant-product AMM: x·y=k"*, *"Slippage"*, and
*"Impermanent loss"* in `4-ethereum-defi-lesson`.

## Files

| File | Role |
| --- | --- |
| `contract/01-ConstantProductAMM_start.sol` | **Your task.** Implement `getAmountOut` and `swap`. |
| `contract/01-ConstantProductAMM.sol` | **Solution / reference.** Full pool + two mock ERC-20s. |

Both files are **self-contained**: a `MinimalERC20` token and the pool live in
one file, so the whole lab runs in the **Remix VM** with no imports.

> The reference pool is **fee-free** so the numbers match the slides exactly. A
> real AMM charges ~0.30% per swap — that fee is how liquidity providers earn.
> Adding it is the extension at the bottom.

---

## Your task

In `01-ConstantProductAMM_start.sol` complete:

1. **`getAmountOut`** — the pricing formula
   `amountOut = (reserveOut · amountIn) / (reserveIn + amountIn)`
   (guard `amountIn > 0` and non-empty reserves first).
2. **`swap`** — pick the in/out sides from `tokenIn`, price it with
   `getAmountOut`, enforce `amountOut >= minAmountOut` (slippage guard), pull
   `amountIn` in with `transferFrom`, pay `amountOut` out with `transfer`, then
   `_sync()`.

## Walkthrough (Remix VM)

Amounts use **18 decimals**, so "100 tokens" = `100000000000000000000` (`100e18`).

1. Compile `01-ConstantProductAMM.sol` (or your `_start` once finished),
   **Solidity 0.8.20+**, Environment **Remix VM**.
2. Deploy two tokens from the **same** account (the deployer holds the supply):
   - `MinimalERC20("EtherToken","ETK", 1000000000000000000000000)` (1,000,000)
   - `MinimalERC20("UsdToken","USDT", 1000000000000000000000000)`
3. Deploy `ConstantProductAMM(ETK_address, USDT_address)`.
   Here **token0 = ETK**, **token1 = USDT**.
4. **Approve** the pool to move your tokens: on **ETK** call
   `approve(AMM_address, 1000000000000000000000000)`; do the same on **USDT**.
5. **Seed liquidity** at a 100 : 200 ratio: on the AMM call
   `addLiquidity(100000000000000000000, 200000000000000000000)`.
   Now `reserve0 = 100e18`, `reserve1 = 200e18`.

### Reproduce the slide numbers (pricing & slippage)

Use `getAmountOut` (a **pure** function — the *call* button, no transaction):

| Call | Returns (wei) | ≈ tokens | Slide |
| --- | --- | --- | --- |
| `getAmountOut(1e18, 100e18, 200e18)` | `1980198019801980198` | **1.98** | close to 1:2 spot |
| `getAmountOut(50e18, 100e18, 200e18)` | `66666666666666666666` | **66.67** | *not* 100 — the curve |
| `getAmountOut(10000e18, 100e18, 200e18)` | `198019801980198019801` | **~198.02** | approaches, never reaches, 200 |

The last row is the point of the module: **you can never extract the whole
200** — as `amountIn → ∞`, `amountOut → reserveOut` but never reaches it (a
1000-token swap already only yields ~181.8; a 10 000-token swap ~198.02). The
pool is self-protecting.

### Execute a real swap and watch the price move

1. `swap(ETK_address, 50000000000000000000, 0)` (swap 50 ETK, no min-out).
   You receive ~66.67 USDT; reserves become `150e18 : 133.33e18`.
2. Read `spotPrice0in1()` **before vs after**: it jumps from `2e18` ($2) toward
   `~0.889e18`. **One swap moved the spot price ~55%.**

> **This is the flash-loan / oracle-manipulation attack in miniature.** A large
> (flash-loaned) swap skews `spotPrice0in1()`; any other contract that reads
> this spot price for *state-changing* logic can be tricked. Defence:
> decentralized feeds / TWAP — see the Oracles and Security modules.

### Observe impermanent loss (optional)

After the swap above, call `removeLiquidity(totalShares)` from the LP account
and compare what you get back (`~150 ETK + ~133.33 USDT`) against the original
`100 ETK + 200 USDT` you deposited. You are **forced to hold more of the token
that fell and less of the one that rose** — that divergence versus simply
holding is impermanent loss. Fees (the extension) are what compensate LPs for it.

## Extension — add the 0.30% fee

Change `getAmountOut` to the Uniswap-V2 formula:

```solidity
uint256 amountInWithFee = amountIn * 997;
amountOut = (reserveOut * amountInWithFee) / (reserveIn * 1000 + amountInWithFee);
```

Re-run `getAmountOut(1e18, 100e18, 200e18)` → **~1.976** instead of 1.98: the
missing slice is the LP fee. This is what makes providing liquidity profitable.

## Discussion prompts

- Why does the constant-*product* curve protect reserves while a constant-*sum*
  line (`x + y = k`) can be drained to zero?
- Deep pool vs thin pool: why does the *same* trade cause far less slippage in a
  deep pool?
- Why must `swap` read reserves from `_sync()` (actual balances) rather than
  trusting a caller-supplied number?

# Lab — Oracles · Consuming a price feed safely

An oracle imports outside data — and outside **risk**. This lab shows why a
contract must **validate** an oracle answer before acting on it. You drive a
mock Chainlink aggregator by hand, feed a naive consumer garbage, then write a
safe consumer that rejects it.

Companion to the slides *"In practice: consuming a price feed (Chainlink)"* and
*"Key takeaways & best practices"* in `3-ethereum-oracles-lesson`.

## Files

| File | Role |
| --- | --- |
| `contract/01-PriceConsumer_naive.sol` | **Complete.** Mock aggregator + `NaivePriceConsumer` that returns the answer with no checks. |
| `contract/02-PriceConsumer_start.sol` | **Your task.** `SafePriceConsumer` with `TODO`s: positivity, freshness, complete-round checks. |
| `contract/02-PriceConsumer.sol` | **Solution.** |

Everything runs in the **Remix VM** — the `MockV3Aggregator` replaces a live
Chainlink feed so no network is needed. It uses the real
`AggregatorV3Interface` shape, so the consumer code is identical to what you'd
deploy against a production feed.

> **Decimals:** USD price feeds report with **8 decimals**, so an answer of
> `2000_00000000` means **$2000.00**. Deploy the mock with `_decimals = 8`.

---

## Part A — see the naive consumer trust garbage (5 min)

1. Paste `01-PriceConsumer_naive.sol`, compile with **Solidity 0.8.20+**,
   Environment **Remix VM**.
2. Deploy **`MockV3Aggregator`** with `_decimals = 8`,
   `_initialAnswer = 200000000000` (= $2000).
3. Deploy **`NaivePriceConsumer`** with the mock's address. Call `getPrice()`
   → `200000000000`. So far so good.
4. Now simulate feed failures on the mock and re-read `getPrice()`:
   - `updateAnswer(0)` → naive consumer returns **0** (a "free" asset).
   - `updateAnswerWithTimestamp(-500000000, 1)` → returns a **negative, ancient**
     price. In a lending market this misprices collateral and triggers wrongful
     liquidations.

## Part B — write the safe consumer (15 min)

1. Open `02-PriceConsumer_start.sol`, complete the four `TODO`s in
   `getSafePrice` (revert on incomplete round, non-positive answer, and staleness).
2. Deploy its `MockV3Aggregator` + `SafePriceConsumer`.
3. Re-run the failure scenarios:

| Mock call | `getSafePrice()` result |
| --- | --- |
| `updateAnswer(200000000000)` (healthy) | returns `200000000000` |
| `updateAnswer(0)` | reverts `NonPositivePrice` |
| `updateAnswerWithTimestamp(200000000000, 1)` | reverts `StalePrice` |
| `updateAnswerWithTimestamp(0, 0)` | reverts `IncompleteRound` |

4. Compare with `02-PriceConsumer.sol`.

### Why these checks

- **Positivity** — a misconfigured or broken feed can report `0` or a negative
  `int256`. Treating that as a price zeroes out collateral value.
- **Freshness** — nodes can stall; a pair can depeg. `updatedAt` tells you the
  answer's age; reject anything older than the feed's heartbeat.
- **Complete round** — `updatedAt == 0` means the round never closed; the answer
  is meaningless.

## Connects back to the Security & DeFi modules

- The single most damaging oracle failure is **price manipulation** (Mango
  Markets, ~$116M). The defence is not just these checks but **not reading a
  spot price from an AMM** in the first place — use a decentralized feed or a
  **TWAP**. Flash loans (DeFi module) make any manipulable spot price instantly
  exploitable.

## Discussion prompts

- Chainlink deprecated `answeredInRound`; what replaced the "is this the latest
  answered round?" check, and why?
- Freshness bound too tight vs too loose — what breaks in each case?
- Why is a view-only price read *not* directly exploitable, but dangerous the
  moment a **state-changing** function consumes it?

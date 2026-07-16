# Commit/Reveal — Rock-Paper-Scissors on Ethereum

A standalone teaching example showing how to play a fair game of
Rock-Paper-Scissors on a public blockchain, where every transaction is
visible to every observer.

The contract is **self-contained** — no `@openzeppelin/contracts`
imports. It is intended as the in-class companion to the slide deck
`commit-reveal.pptx`.

## Folder layout

```
commit-reveal-example/
├── contract/
│   └── RockPaperScissors.sol      ← the full game logic, MIT-licensed
└── README.md
```

## The problem in one paragraph

On a public chain, every transaction sits in the mempool — visible to
every observer — for several seconds before it is mined. A naive
implementation of Rock-Paper-Scissors that asks each player to call
`play(move)` would let the second player **read** the first player's
move from the mempool and pick the winning counter, paying more gas to
get mined first. This is the same class of vulnerability that drives
MEV (Maximum Extractable Value) on Ethereum mainnet.

## The protocol

```
Phase 1 (commit):   each player publishes  H(move ‖ salt ‖ player)
Phase 2 (reveal):   each player publishes  (move, salt)
                    contract recomputes    H(move ‖ salt ‖ player)
                    accepts the reveal iff the two hashes match
```

Three ingredients are non-negotiable.

| Ingredient                  | Why it must be there                                                                |
| --------------------------- | ----------------------------------------------------------------------------------- |
| **`salt`** (random 32 bytes) | Without it the move space has only 3 entries; an attacker brute-forces `H(Rock)`, `H(Paper)`, `H(Scissors)` in microseconds. |
| **`player` address** in the hash | Otherwise player 2 can **copy** player 1's commit hash bit-for-bit; later, when player 1 reveals `(move, salt)`, player 2 replays the same pair and forces a draw. |
| **A reveal deadline**        | If only one player reveals, funds would otherwise be locked forever. Either player can claim the pot after a timeout. |

## Why this contract does NOT use `ReentrancyGuard`

Both state-mutating paths that perform an external call follow the
**Checks-Effects-Interactions (CEI)** discipline:

- `reveal()` makes **no external call**. It updates storage and may
  call `_settle()`, which again only updates storage.
- `withdraw()` zeroes `pendingWithdrawals[msg.sender]` **before** the
  low-level call. A re-entrant call from the recipient sees a zero
  balance and reverts at the `NothingToWithdraw` check.

Adding a guard would cost ~6 000 extra gas per call with no security
benefit on this particular contract. The standalone discipline is the
defence here — it is exactly the kind of trade-off you want students to
understand.

## State machine

```
       createGame() ─────────────►  AwaitingP2
                                       │
                            joinGame() │
                                       ▼
                                 Committing  ─── commit() x2 ──►  Revealing
                                       │                              │
                       commit timeout  │                              │  reveal() x2
                                       │                              │
                                       ▼                              ▼
                                 Settled  ◄───── settle ───── Revealing
                                       ▲                              │
                                       │            reveal timeout    │
                                       └──────────────────────────────┘
```

Five reachable states; every transition emits an event for off-chain
indexers.

## Lab walkthrough — Remix

1. **Open Remix** at <https://remix.ethereum.org>. Paste the contract,
   pick Solidity 0.8.20+, and compile.
2. **Account A → `createGame`** with VALUE = 0.01 SEP. Note the `gameId`
   returned in the receipt (e.g. `0`).
3. **Account B → `joinGame(0)`** with VALUE = 0.01 SEP.
4. **Off-chain:** compute commit hashes via `makeCommitment(move, salt, you)`.
   Remix's *call* button on this `pure` function returns the hash
   instantly, without sending a transaction.
5. **A → `commit(0, hashA)`**, **B → `commit(0, hashB)`**.
6. **A → `reveal(0, moveA, saltA)`**, **B → `reveal(0, moveB, saltB)`**.
   The `Settled` event announces the winner.
7. **Winner → `withdraw()`** — the pot lands in the winner's wallet.

To exercise the **timeout path**, have A commit but B do *not*. Wait
until `block.timestamp > commitDeadline` (one hour by default; you can
shorten `COMMIT_WINDOW` during a lab to make this practical), then call
`claimCommitTimeout(0)` from any account.

## Playing the game from ethers.js

```js
import { ethers } from "ethers";

const stake = ethers.parseEther("0.01");
const ROCK = 1, PAPER = 2, SCISSORS = 3;

// ── Alice creates the game ──
const txA = await rps.connect(alice).createGame({ value: stake });
const rcptA = await txA.wait();
const gameId = rcptA.logs[0].args.gameId;

// ── Bob joins ──
await (await rps.connect(bob).joinGame(gameId, { value: stake })).wait();

// ── Alice builds her commit off-chain ──
const aliceMove = PAPER;
const aliceSalt = ethers.hexlify(ethers.randomBytes(32));
const aliceCommit = ethers.solidityPackedKeccak256(
  ["uint8",  "bytes32", "address"],
  [aliceMove, aliceSalt, alice.address]
);
await (await rps.connect(alice).commit(gameId, aliceCommit)).wait();

// ── Bob builds his commit off-chain ──
const bobMove = SCISSORS;
const bobSalt = ethers.hexlify(ethers.randomBytes(32));
const bobCommit = ethers.solidityPackedKeccak256(
  ["uint8",  "bytes32", "address"],
  [bobMove,  bobSalt,   bob.address]
);
await (await rps.connect(bob).commit(gameId, bobCommit)).wait();

// ── Reveal phase ──
await (await rps.connect(alice).reveal(gameId, aliceMove, aliceSalt)).wait();
await (await rps.connect(bob).reveal(gameId,   bobMove,   bobSalt)).wait();
// Scissors cut Paper → Bob wins the pot.

// ── Winner collects ──
await (await rps.connect(bob).withdraw()).wait();
```

### Three things students must internalise

1. **Persist the salt locally.** If a player loses their salt before the
   reveal phase, they cannot reveal and will be timed out. In a real
   dApp the salt should be stored in `localStorage` or derived
   deterministically from a wallet-signed message.
2. **Use `solidityPackedKeccak256`**, not `keccak256(toUtf8Bytes(...))`.
   The Solidity encoding is `abi.encodePacked(uint8, bytes32, address)`
   — 53 bytes total — and the JS side must reproduce the exact byte
   sequence.
3. **The reveal must come from the *same* address as the commit.** A
   reveal sent from another account makes `msg.sender` differ and the
   hash check fails with `CommitMismatch`.

## Security analysis at a glance

| Attack                                          | Defence                                                                  |
| ----------------------------------------------- | ------------------------------------------------------------------------ |
| Mempool sniffing of the move                    | The commit publishes only `H(move ‖ salt ‖ player)`.                     |
| Brute-force of the 3-move space                 | 256-bit salt — pre-image space becomes 3 · 2²⁵⁶.                         |
| Commit-copying by player 2                      | `msg.sender` is hashed into the commit; replaying breaks the hash check. |
| Refusing to reveal                              | `claimRevealTimeout(gameId)` awards the pot to the revealer.             |
| Refusing to commit                              | Symmetric — `claimCommitTimeout(gameId)`.                                |
| Re-entry on payout                              | CEI: balance is zeroed before the external call (no guard needed).       |
| Hostile smart-contract recipient blocking payout | Pull-payment pattern — only that recipient suffers.                      |
| Self-play (Alice vs. Alice)                     | `joinGame` reverts with `SelfPlay`.                                      |
| Invalid enum value                              | Solidity rejects out-of-range; `Move.None` is explicitly forbidden.      |

## Possible extensions (exam material)

| Extension                          | Idea                                                                                       |
| ---------------------------------- | ------------------------------------------------------------------------------------------ |
| Best-of-N rounds                   | Track `roundsWon[player]`; players re-commit per round.                                    |
| ERC-20 stakes                      | Replace `msg.value` with `SafeERC20` transfers; require allowance pre-game.                |
| House fee                          | Skim e.g. 1 % of each pot to a treasury before paying the winner.                          |
| Lobby with searchable open games   | Maintain an `openGameIds[]` array and emit a `GameOpened` event with the stake amount.     |
| EIP-712-signed commits             | Players sign a typed message off-chain; a relayer submits commits (gasless gameplay).      |
| Verifiable randomness fallback     | If both players time out on reveal, draw a random winner via Chainlink VRF instead of refunding. |
| Lizard-Spock variant               | Five-move version of the game; the cyclic comparison generalises naturally.                |

## References

- The original commit-reveal idea — Manuel Blum, *Coin Flipping by Telephone* (1983).
- Solidity `keccak256` and `abi.encodePacked` semantics — <https://docs.soliditylang.org/en/latest/units-and-global-variables.html#abi-encoding-and-decoding-functions>
- Checks-Effects-Interactions pattern — <https://docs.soliditylang.org/en/latest/security-considerations.html#use-the-checks-effects-interactions-pattern>
- Maximum Extractable Value (MEV) overview — <https://ethereum.org/en/developers/docs/mev/>
- The DAO attack post-mortem (June 2016) — <https://www.coindesk.com/learn/understanding-the-dao-attack/>

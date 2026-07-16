# Lab — DAO · Token-weighted governance over a treasury

Build the core loop of an on-chain DAO: **propose → vote (token-weighted) →
timelock → execute**. The DAO holds an ETH treasury; a passed proposal makes the
DAO itself spend from it. You will also see the classic governance weakness —
**flash-loan vote-buying** — and how snapshots fix it.

Companion to the DAO deck (`5-dao-lesson`).

## Files

| File | Role |
| --- | --- |
| `contract/01-SimpleDAO_start.sol` | **Your task.** Implement `vote` and the pass/quorum check in `execute`. |
| `contract/01-SimpleDAO.sol` | **Solution.** Full DAO + governance token. |

Self-contained (no imports); runs in the **Remix VM**.

---

## Your task

In `01-SimpleDAO_start.sol` complete:

1. **`vote(id, support)`** — reject votes after `endTime`, reject double votes,
   read `weight = token.balanceOf(msg.sender)` (revert if 0), record the vote,
   and add the weight to `forVotes` or `againstVotes`.
2. **`execute(id)`** — a proposal passes iff `forVotes > againstVotes` **and**
   `forVotes >= quorumVotes`. Keep `p.executed = true` **before** the external
   call (CEI, so it can't be re-run or re-entered).

## Walkthrough (Remix VM)

> Use **short timings** so you can complete it live: `votingPeriod = 60`
> (seconds), `timelockDelay = 0`. Real DAOs use days. In the Remix VM, each
> transaction stamps the current wall-clock time, so waiting ~60 real seconds
> between voting and executing is enough to cross the deadline.

1. Compile `01-SimpleDAO.sol` (or your finished `_start`), **Solidity 0.8.20+**,
   Environment **Remix VM**.
2. Deploy **`GovToken`** with `initialSupply = 1000000000000000000000` (1000 GOV)
   from **Account A**.
3. Distribute voting power: from A, `transfer` 400 GOV
   (`400000000000000000000`) to **Account B** and 100 GOV to **Account C**.
   (A keeps 500, B has 400, C has 100.)
4. Deploy **`SimpleDAO`** with:
   - `governanceToken` = GovToken address
   - `_quorumVotes` = `300000000000000000000` (300 GOV must vote FOR)
   - `_votingPeriod` = `60`
   - `_timelockDelay` = `0`
5. **Fund the treasury:** in Deploy & Run, set **VALUE = 5 ether**, pick the
   `receive`/*low-level interactions* field (or send from an account) to the DAO
   address. Confirm `treasuryBalance()` = `5000000000000000000`.
6. **Propose** to pay 1 ETH to Account C. From A, call:
   - `target` = Account C's address
   - `value` = `1000000000000000000` (1 ETH)
   - `data` = `0x` (a plain ETH transfer needs no calldata)
   - `description` = `"Pay grant to C"`
   Note the returned `id` = `1`.
7. **Vote:** A votes `true` (weight 500), C votes `true` (weight 100), B votes
   `false` (weight 400). Tally: **for = 600, against = 400**.
8. **Wait ~60 seconds**, then call `execute(1)`.
   - `forVotes (600) > againstVotes (400)` ✓ and `forVotes (600) >= quorum (300)` ✓
   - The DAO sends 1 ETH to C; `treasuryBalance()` → `4000000000000000000`.
9. Try to `execute(1)` again → reverts `AlreadyExecuted`.

**Failure cases to try:** execute before the deadline (`VotingOngoing`); a
proposal where only C votes for (100 < 300 quorum → `ProposalRejected`);
voting twice from one account (`AlreadyVoted`).

## Why the timelock and quorum matter

- **Quorum** stops a tiny, unrepresentative turnout from moving the treasury.
- **Timelock** gives members a window to react (exit, alert, contest) between a
  proposal passing and it taking effect — the standard defence against a
  malicious proposal sneaking through.
- **CEI on execute** means a proposal that calls back into the DAO can't cause a
  double-spend: `executed` is already `true`.

## Extension — defeat flash-loan vote-buying (the real lesson)

This lab counts `balanceOf` **at vote time**. An attacker can flash-borrow a
huge amount of GOV, `vote`, and repay in the same transaction — buying the
outcome for one block's fee. This is the **Beanstalk (April 2022, ~$182M)**
attack.

The production fix is to **snapshot voting power at the proposal's creation
block** using checkpointed balances, so tokens acquired *after* a proposal
exists carry no weight:

- OpenZeppelin **`ERC20Votes`** (checkpointed balances + delegation) + the
  **`Governor`** framework, or a Compound/Bravo-style `getPriorVotes`.
- Combined with a **timelock** (OpenZeppelin `TimelockController`) so even a
  passed proposal cannot execute instantly.

Discuss: why does snapshotting at *proposal creation* (not vote time) neutralise
the flash loan, while a timelock alone does not?

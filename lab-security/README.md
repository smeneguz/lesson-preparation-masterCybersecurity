# Lab — Smart Contract Security · Reentrancy

The flagship vulnerability of the Security module, live in Remix. You will
**drain a vault in one transaction**, then fix it with the two standard
defences: **Checks-Effects-Interactions (CEI)** and a **reentrancy lock**.

This lab is the practical companion to slides *"1 · Reentrancy — the
vulnerability / the attack / prevention"* in `2-ethereum-security-lesson`.

## Files

| File | Role |
| --- | --- |
| `contract/01-EtherStore_vulnerable.sol` | **Complete.** The vulnerable `EtherStore` vault **and** the `Attack` contract. Run it and watch the drain. |
| `contract/02-SafeEtherStore_start.sol` | **Your task.** Same vault, with `TODO`s: apply CEI and complete the reentrancy lock. |
| `contract/02-SafeEtherStore.sol` | **Solution.** The fixed vault. Compare after you try. |

All contracts are **self-contained** (no imports) so they compile and run in
the **Remix JavaScript VM** with no network, no MetaMask, no faucet.

---

## Part A — reproduce the exploit (5 min)

1. Open <https://remix.ethereum.org>, create `EtherStore.sol`, paste
   `01-EtherStore_vulnerable.sol`, compile with **Solidity 0.8.20+**.
2. In **Deploy & Run**, set **Environment = Remix VM (Cancun)**.
3. Deploy **`EtherStore`**.
4. Simulate honest users: with **VALUE = 1 ether** (pick the *Ether* unit),
   call `deposit()` from **three different accounts** (switch the *Account*
   dropdown). Now `vaultBalance()` returns **3 ETH**.
5. Deploy **`Attack`**, passing the `EtherStore` address to the constructor.
6. From a *fresh* account, call `attack()` with **VALUE = 1 ether**.
7. Read `vaultBalance()` → **0**. Read the `Attack` contract's `loot()` → **~4 ETH**
   (the 3 victims' ether **plus** the attacker's own seed). Call `collect()` to
   sweep it out.

> **What happened:** the vault paid the `Attack` contract, which re-entered
> `withdraw()` before `balances` was zeroed, looping until the vault was empty.

## Part B — fix it yourself (15 min)

1. Open `02-SafeEtherStore_start.sol` and complete the four `TODO`s:
   - **TODO 1-3:** finish the `nonReentrant` mutex (reject re-entry, lock, unlock).
   - **TODO 4:** rewrite `withdraw()` in **CEI order** and add `nonReentrant`.
2. Compile, deploy `SafeEtherStore`, re-run the *same* attack from Part A.
   - `attack()` now **reverts**; the vault keeps the victims' funds.
3. Confirm the honest path still works: `deposit()` then `withdraw()` from a
   normal account succeeds.
4. Compare with `02-SafeEtherStore.sol`.

### Why the fix works

- **CEI alone stops the attack.** Once `balances[msg.sender] = 0` runs *before*
  the external call, the re-entrant `withdraw()` reads a zero balance and
  reverts at the `NothingToWithdraw` check. The state is always consistent
  before control leaves the contract.
- **The mutex is defence-in-depth.** Even if a later refactor re-introduced a
  bad ordering, `nonReentrant` would still block the second entry. Production
  code should inherit OpenZeppelin's `ReentrancyGuard` rather than the teaching
  copy here.

> **Trade-off worth noting:** for a function that already follows CEI and makes
> a single trusted call, the guard adds ~2 300 gas and is sometimes omitted (as
> in the commit-reveal `withdraw()`). Use CEI **always**; add the guard whenever
> a function makes external calls and you want a second safety net.

## Discussion prompts

- Why does forwarding only 2 300 gas (`transfer`/`send`) *usually* block this
  attack — and why is it **not** a reliable defence anymore? (Hint: gas repricing,
  contract recipients, EIP-7702.)
- The attack drains in **one** transaction. Why does that make monitoring /
  pausing an insufficient defence on its own?
- Where else do external calls hide? (ERC-721 `onERC721Received`, ERC-777
  `tokensReceived`, read-only reentrancy through a `view` getter.)

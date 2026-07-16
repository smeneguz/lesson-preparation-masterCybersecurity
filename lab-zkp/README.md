# Lab — ZKP · A Schnorr proof of knowledge, verified on-chain

The "hello world" of zero-knowledge: prove you **know a secret `x`** with
`P = x·G` **without revealing `x`**. This is a real ZKP — a **Sigma protocol**
made non-interactive with the **Fiat-Shamir** heuristic — and the exact idea
behind Schnorr/EdDSA signatures and the "proof of knowledge" core of many ZK
systems.

It runs **entirely in the Remix VM**, verified on-chain with Ethereum's bn128
precompiles (`0x06` ECADD, `0x07` ECMUL) — the same precompiles a real Groth16
zk-SNARK verifier uses (plus pairing `0x08`).

Companion to the ZKP deck (`6-zkp-lesson`).

## The math (one line)

```
Prover:   R = k·G ,   c = H(P, R) mod n ,   s = k + c·x  (mod n)      proof = (R, s)
Verifier: accept  ⇔  s·G  ==  R + c·P
Why:      s·G = (k + c·x)·G = k·G + c·(x·G) = R + c·P     ✓
Hiding:   R is random, s is masked by the random nonce k → x never leaks.
```

## Files

| File | Role |
| --- | --- |
| `contract/01-SchnorrZKP_start.sol` | **Your task.** Implement `SchnorrVerifier.verify`. |
| `contract/01-SchnorrZKP.sol` | **Solution.** Verifier + curve library + prover harness. |

> **Honesty note.** In reality the **prover runs off-chain** — only `(R, s)` and
> the public `P` ever touch the chain, so `x` stays secret. The `SchnorrProver`
> contract computes a proof *on-chain* only so the lab is self-contained; it
> takes `x` as input, which reveals it to that one call. Treat the prover as a
> **test harness**; the **verifier** is the real, deployable artifact.

---

## Your task

In `01-SchnorrZKP_start.sol`, implement `verify` (see the step list in its
`TODO`): reject `s >= N`, recompute the challenge `c`, then check
`s·G == R + c·P` using `BN128.ecMul` / `BN128.ecAdd`.

## Walkthrough (Remix VM)

1. Compile `01-SchnorrZKP.sol` (or your finished `_start`), **Solidity 0.8.20+**,
   Environment **Remix VM**.
2. Deploy **`SchnorrProver`** and **`SchnorrVerifier`**.
3. On the prover, pick any secret and nonce **in range** `[1, n-1]` (any normal
   integer like the ones below is fine) and call:
   `prove(x = 12345, k = 67890)`.
   It returns five numbers: `Px, Py, Rx, Ry, s`.
4. **Copy those exact values** into the verifier's `verify(Px, Py, Rx, Ry, s)`
   → **`true`**. You just verified knowledge of `x` while the verifier only ever
   saw `P`, `R`, and `s`.
5. **Tamper** with the proof to see soundness: call `verify` again with `s + 1`
   (or any changed digit of `s`) → **`false`**. A forged response cannot satisfy
   the equation without knowing `x`.

> Use **different values** per run (vary `x` and `k`) — do not hardcode expected
> outputs, because the point `P` and proof depend on your inputs. `k` must be
> **fresh and random** every time: reusing a nonce `k` across two proofs for the
> same `x` leaks the secret (the same flaw that broke the Sony PS3 ECDSA keys).

## Why this is zero-knowledge (and what it is not)

- **Complete:** an honest prover who knows `x` always convinces the verifier.
- **Sound:** without `x`, forging `(R, s)` that satisfies `s·G = R + c·P` is as
  hard as computing a discrete log.
- **Zero-knowledge:** the transcript `(R, c, s)` is simulatable — it reveals
  nothing about `x` beyond "the prover knows it".

This proves knowledge of **one discrete log**. General-purpose ZK (proving *"I
ran this program correctly"* / *"I own a leaf in this Merkle tree"*) needs a
full proof system — **zk-SNARKs** (e.g. Groth16, PLONK) or **zk-STARKs** — which
compile an arbitrary circuit into a succinct proof. Those Groth16 verifiers run
on-chain using the very same bn128 precompiles you used here, plus the
**pairing** precompile `0x08`. This lab is the conceptual seed of all of it.

## Discussion prompts

- Where does the **interactivity** go in Fiat-Shamir, and what does the verifier
  have to trust about `H` for the non-interactive version to stay sound?
- Why does **nonce reuse** leak `x`? (Write the two response equations and solve.)
- A real private-payments system (Tornado-style) proves *Merkle membership +
  a nullifier* in zero knowledge. Which part is "proof of knowledge" like this
  lab, and which part needs a full SNARK circuit?

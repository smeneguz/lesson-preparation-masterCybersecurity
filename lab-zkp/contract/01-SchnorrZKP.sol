// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Zero-Knowledge Proofs · Schnorr proof of knowledge (the SOLUTION)
//
//  The "hello world" of zero-knowledge: a non-interactive proof that you KNOW a
//  secret x such that  P = x·G  — WITHOUT revealing x. This is a real ZKP (a
//  Sigma protocol made non-interactive with the Fiat-Shamir heuristic) and the
//  building block behind Schnorr/EdDSA signatures and many ZK systems.
//
//  STATEMENT (public):   a point P on the bn128 curve (G is the generator).
//  WITNESS  (secret):    x with P = x·G   (a discrete logarithm).
//
//  PROTOCOL (Fiat-Shamir, non-interactive):
//    Prover picks random nonce k, sets  R = k·G
//                                   c = H(P, R) mod n           (the challenge)
//                                   s = k + c·x  (mod n)         (the response)
//    Proof = (R, s).
//  Verifier accepts iff        s·G  ==  R + c·P.
//    Correctness: s·G = (k + c·x)·G = k·G + c·(x·G) = R + c·P.  ✓
//    Zero-knowledge: R is uniformly random, s is masked by k → x never leaks.
//
//  We verify on-chain using Ethereum's bn128 precompiles:
//    0x06 = ECADD (point addition),  0x07 = ECMUL (scalar multiplication).
//
//  ── Honesty note ─────────────────────────────────────────────────────────────
//  In real use the PROVER runs OFF-CHAIN (only the proof (R, s) and the public P
//  ever touch the chain, so x stays secret). The `SchnorrProver` helper below
//  computes a proof ON-CHAIN purely so the whole lab is self-contained in Remix —
//  it takes x as input, which of course "reveals" x to that call. Treat the
//  prover as a test harness; the VERIFIER is the real, deployable artifact.
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Thin wrappers over the bn128 (alt_bn128) G1 precompiles.
library BN128 {
    // Field modulus of the base field F_p (points live here).
    uint256 internal constant P =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
    // Order of the G1 group (scalars live in F_n). n is prime.
    uint256 internal constant N =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Generator G of G1.
    uint256 internal constant GX = 1;
    uint256 internal constant GY = 2;

    /// @dev (rx, ry) = s · (x, y) via the ECMUL precompile at 0x07.
    function ecMul(uint256 x, uint256 y, uint256 s)
        internal
        view
        returns (uint256 rx, uint256 ry)
    {
        uint256[3] memory input = [x, y, s];
        uint256[2] memory out;
        bool ok;
        assembly {
            ok := staticcall(gas(), 0x07, input, 0x60, out, 0x40)
        }
        require(ok, "ECMUL failed");
        rx = out[0];
        ry = out[1];
    }

    /// @dev (rx, ry) = (x1, y1) + (x2, y2) via the ECADD precompile at 0x06.
    function ecAdd(uint256 x1, uint256 y1, uint256 x2, uint256 y2)
        internal
        view
        returns (uint256 rx, uint256 ry)
    {
        uint256[4] memory input = [x1, y1, x2, y2];
        uint256[2] memory out;
        bool ok;
        assembly {
            ok := staticcall(gas(), 0x06, input, 0x80, out, 0x40)
        }
        require(ok, "ECADD failed");
        rx = out[0];
        ry = out[1];
    }
}

/// @title The verifier — the real, deployable half of a ZK system.
contract SchnorrVerifier {
    using BN128 for uint256;

    /// @notice The Fiat-Shamir challenge  c = H(P, R) mod n.
    /// @dev    Deterministic: the prover and verifier MUST hash identically.
    function challenge(uint256 Px, uint256 Py, uint256 Rx, uint256 Ry)
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(Px, Py, Rx, Ry))) % BN128.N;
    }

    /// @notice Verify a Schnorr proof (R, s) for the public statement P.
    /// @return ok true iff  s·G == R + c·P.
    function verify(
        uint256 Px,
        uint256 Py,
        uint256 Rx,
        uint256 Ry,
        uint256 s
    ) public view returns (bool ok) {
        if (s >= BN128.N) return false; // response must be a valid scalar

        uint256 c = challenge(Px, Py, Rx, Ry);

        // left = s·G
        (uint256 lx, uint256 ly) = BN128.ecMul(BN128.GX, BN128.GY, s);

        // right = R + c·P
        (uint256 cpx, uint256 cpy) = BN128.ecMul(Px, Py, c);
        (uint256 rx, uint256 ry) = BN128.ecAdd(Rx, Ry, cpx, cpy);

        ok = (lx == rx && ly == ry);
    }
}

/// @title The prover — a test harness ONLY (see the honesty note at the top).
contract SchnorrProver {
    /// @notice Public key / statement P = x·G for a secret x.
    function pubKey(uint256 x) public view returns (uint256 Px, uint256 Py) {
        require(x != 0 && x < BN128.N, "x out of range");
        (Px, Py) = BN128.ecMul(BN128.GX, BN128.GY, x);
    }

    /// @notice Produce a full proof for secret `x` using nonce `k`.
    /// @dev    Returns P too, so you can paste the exact values into `verify`.
    ///         In production this runs off-chain; `k` MUST be random and secret.
    function prove(uint256 x, uint256 k)
        public
        view
        returns (uint256 Px, uint256 Py, uint256 Rx, uint256 Ry, uint256 s)
    {
        require(x != 0 && x < BN128.N, "x out of range");
        require(k != 0 && k < BN128.N, "k out of range");

        (Px, Py) = BN128.ecMul(BN128.GX, BN128.GY, x); // P = x·G
        (Rx, Ry) = BN128.ecMul(BN128.GX, BN128.GY, k); // R = k·G

        uint256 c = uint256(keccak256(abi.encodePacked(Px, Py, Rx, Ry))) % BN128.N;
        // s = k + c·x (mod n)
        s = addmod(k, mulmod(c, x, BN128.N), BN128.N);
    }
}

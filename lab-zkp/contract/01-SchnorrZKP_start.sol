// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Zero-Knowledge Proofs · Schnorr proof of knowledge (YOUR TASK)
//
//  Prove you KNOW a secret x with  P = x·G  without revealing x.
//
//  PROTOCOL (Fiat-Shamir):  R = k·G,  c = H(P,R) mod n,  s = k + c·x mod n.
//  Proof = (R, s). Verifier accepts iff   s·G == R + c·P.
//
//  YOUR TASK: implement `SchnorrVerifier.verify` using the BN128 helpers.
//  The prover harness and the elliptic-curve library are provided. See README.
//
//  Honesty note: the prover runs off-chain in reality; here it is an on-chain
//  test harness so everything works in Remix. The VERIFIER is the real artifact.
// ─────────────────────────────────────────────────────────────────────────────

library BN128 {
    uint256 internal constant P =
        21888242871839275222246405745257275088696311157297823662689037894645226208583;
    uint256 internal constant N =
        21888242871839275222246405745257275088548364400416034343698204186575808495617;
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

contract SchnorrVerifier {
    /// @notice The Fiat-Shamir challenge  c = H(P, R) mod n.
    function challenge(uint256 Px, uint256 Py, uint256 Rx, uint256 Ry)
        public
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(Px, Py, Rx, Ry))) % BN128.N;
    }

    /// @notice Verify a Schnorr proof (R, s) for the public statement P.
    /// @dev    TODO: implement the check  s·G == R + c·P.
    ///           1. reject if s >= BN128.N  (return false).
    ///           2. c = challenge(Px, Py, Rx, Ry).
    ///           3. left  = s·G          → BN128.ecMul(BN128.GX, BN128.GY, s).
    ///           4. cP    = c·P          → BN128.ecMul(Px, Py, c).
    ///           5. right = R + cP       → BN128.ecAdd(Rx, Ry, cP.x, cP.y).
    ///           6. return (left.x == right.x && left.y == right.y).
    function verify(
        uint256 Px,
        uint256 Py,
        uint256 Rx,
        uint256 Ry,
        uint256 s
    ) public view returns (bool ok) {
        // TODO: implement the verification equation. Replace the stub.
        Px; Py; Rx; Ry; s;
        ok = false;
    }
}

contract SchnorrProver {
    function pubKey(uint256 x) public view returns (uint256 Px, uint256 Py) {
        require(x != 0 && x < BN128.N, "x out of range");
        (Px, Py) = BN128.ecMul(BN128.GX, BN128.GY, x);
    }

    function prove(uint256 x, uint256 k)
        public
        view
        returns (uint256 Px, uint256 Py, uint256 Rx, uint256 Ry, uint256 s)
    {
        require(x != 0 && x < BN128.N, "x out of range");
        require(k != 0 && k < BN128.N, "k out of range");

        (Px, Py) = BN128.ecMul(BN128.GX, BN128.GY, x);
        (Rx, Ry) = BN128.ecMul(BN128.GX, BN128.GY, k);

        uint256 c = uint256(keccak256(abi.encodePacked(Px, Py, Rx, Ry))) % BN128.N;
        s = addmod(k, mulmod(c, x, BN128.N), BN128.N);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Smart Contract Security · Reentrancy (YOUR TASK: make it safe)
//
//  Start from this file. It is the SAME vault as 01-EtherStore_vulnerable.sol,
//  but this time YOU fix the withdraw path. Apply BOTH standard defences:
//
//    1) Checks-Effects-Interactions (CEI)
//         Do every CHECK first, then apply every EFFECT (state update), and
//         make the external INTERACTION the very last thing the function does.
//
//    2) A reentrancy lock (mutex)
//         A boolean flag that is raised on entry and lowered on exit; any
//         re-entrant call reverts. In production you would inherit
//         OpenZeppelin's `ReentrancyGuard`; here we implement a minimal one
//         inline so the file stays self-contained for Remix.
//
//  Look for the `TODO` markers. When you are done, re-run the Attack contract
//  from lab file 01 against THIS contract: the drain must now fail and only
//  the attacker's own 1 ETH may ever come back out.
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Minimal reentrancy lock. Inherit it and mark a function
///         `nonReentrant` to forbid re-entry.
abstract contract ReentrancyGuard {
    uint256 private _locked = 1; // 1 = unlocked, 2 = locked

    modifier nonReentrant() {
        // TODO 1: revert if `_locked` is already 2 (a re-entrant call).
        //         Use a require or a custom error.

        // TODO 2: set `_locked = 2` BEFORE running the function body.

        _;

        // TODO 3: reset `_locked = 1` AFTER the function body.
    }
}

/// @title A safe ether vault — your job is to complete `withdraw`.
contract SafeEtherStore is ReentrancyGuard {
    mapping(address => uint256) public balances;

    error NothingToWithdraw();
    error TransferFailed();

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice Withdraw your whole balance — safely.
    /// @dev    TODO 4: rewrite the body in Checks-Effects-Interactions order
    ///         and add the `nonReentrant` modifier to the function signature.
    ///
    ///         Correct order:
    ///           CHECK       read the balance; revert NothingToWithdraw if 0
    ///           EFFECT      set balances[msg.sender] = 0
    ///           INTERACTION (bool ok, ) = msg.sender.call{value: amount}("")
    ///                       revert TransferFailed if !ok
    function withdraw() external {
        // TODO 4: implement CEI here (and add `nonReentrant` above).
    }

    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

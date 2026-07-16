// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Smart Contract Security · Reentrancy (the SOLUTION)
//
//  The vault is fixed with BOTH defences taught in the slides:
//
//    1) Checks-Effects-Interactions — `withdraw` zeroes the balance BEFORE the
//       external call. A re-entrant call now reads a zero balance and reverts
//       at NothingToWithdraw. This alone already defeats the attack.
//
//    2) A reentrancy lock (`nonReentrant`) — belt-and-braces. Even a future
//       refactor that accidentally re-introduced a bad ordering would still be
//       blocked by the mutex. In production, inherit OpenZeppelin's
//       `ReentrancyGuard` (or `ReentrancyGuardTransient`, EIP-1153) instead of
//       this teaching copy.
//
//  Re-run the Attack contract from 01-EtherStore_vulnerable.sol against this
//  contract: `attack()` reverts, the drain is impossible, and the attacker can
//  only ever get its own 1 ETH back.
// ─────────────────────────────────────────────────────────────────────────────

/// @notice Minimal reentrancy lock (a mutex). Mirrors OpenZeppelin's design.
abstract contract ReentrancyGuard {
    uint256 private _locked = 1; // 1 = unlocked, 2 = locked

    error ReentrantCall();

    modifier nonReentrant() {
        if (_locked == 2) revert ReentrantCall(); // CHECK: reject re-entry
        _locked = 2; // lock before the body
        _;
        _locked = 1; // unlock after the body
    }
}

/// @title A safe ether vault.
contract SafeEtherStore is ReentrancyGuard {
    mapping(address => uint256) public balances;

    error NothingToWithdraw();
    error TransferFailed();

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice Withdraw your whole balance — safely.
    /// @dev    Checks-Effects-Interactions, guarded by `nonReentrant`.
    function withdraw() external nonReentrant {
        // CHECK
        uint256 amount = balances[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // EFFECT — state is consistent BEFORE we hand over control.
        balances[msg.sender] = 0;

        // INTERACTION — last. A re-entrant withdraw() now finds a zero
        // balance and reverts at the CHECK above.
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }

    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

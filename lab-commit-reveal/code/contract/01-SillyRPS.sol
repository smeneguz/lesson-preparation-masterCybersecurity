// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract SillyRockPaperScissors {
    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

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

    // ───────────── Events ─────────────

    event GameCreated(
        uint256 indexed gameId,
        address indexed player1,
        uint256 stake
    );
    event PlayerJoined(uint256 indexed gameId, address indexed player2);
    event Moved(uint256 indexed gameId, address indexed player, Move move);
    event Settled(uint256 indexed gameId, address winner, uint256 payout);
    event Withdrawn(address indexed who, uint256 amount);

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
    function createGame() external payable returns (uint256 gameId) {
        if (msg.value == 0) revert ZeroStake();

        gameId = nextGameId++;
        Game storage g = games[gameId];
        g.player1 = msg.sender;
        g.stake = msg.value;
        g.phase = Phase.AwaitingP2;

        emit GameCreated(gameId, msg.sender, msg.value);
    }

    /// @notice Join an open game, matching the creator's stake.
    function joinGame(uint256 gameId) external payable {
        Game storage g = games[gameId];
        if (g.phase != Phase.AwaitingP2) revert InvalidPhase();
        if (msg.value != g.stake) revert WrongStake(msg.value, g.stake);
        if (msg.sender == g.player1) revert SelfPlay();

        g.player2 = msg.sender;
        g.phase = Phase.Moving;

        emit PlayerJoined(gameId, msg.sender);
    }

    function cancelGame(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.AwaitingP2) revert InvalidPhase();
        if (msg.sender != g.player1) revert NotPlayer();

        pendingWithdrawals[g.player1] += g.stake;
        g.phase = Phase.Settled;
        emit Settled(gameId, address(0), 0);
    }

    function move(uint256 gameId, Move m) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.Moving) revert InvalidPhase();
        if (m == Move.None) revert InvalidMove();

        if (msg.sender == g.player1) {
            if (g.move1 != Move.None) revert AlreadyMoved();
            g.move1 = m;
        } else if (msg.sender == g.player2) {
            if (g.move2 != Move.None) revert AlreadyMoved();
            g.move2 = m;
        } else {
            revert NotPlayer();
        }

        emit Moved(gameId, msg.sender, m);

        // Both revealed: settle immediately. _settle only writes storage,
        // it does NOT make external calls — so this is safe.
        if (g.move1 != Move.None && g.move2 != Move.None) {
            _settle(gameId);
        }
    }

    // ───────────── 4. Settlement ─────────────

    function _settle(uint256 gameId) internal {
        Game storage g = games[gameId];
        address winner = _winner(g.move1, g.move2, g.player1, g.player2);
        uint256 pot = g.stake * 2;

        if (winner == address(0)) {
            // Draw — refund each player their own stake.
            pendingWithdrawals[g.player1] += g.stake;
            pendingWithdrawals[g.player2] += g.stake;
        } else {
            pendingWithdrawals[winner] += pot;
        }

        g.phase = Phase.Settled;
        emit Settled(gameId, winner, winner == address(0) ? 0 : pot);
    }

    /// @dev Returns the winning address, or `address(0)` on a draw.
    function _winner(
        Move a,
        Move b,
        address pa,
        address pb
    ) internal pure returns (address) {
        if (a == b) return address(0);

        // The cyclic order of R-P-S: Rock beats Scissors, Scissors beats
        // Paper, Paper beats Rock.
        if (
            (a == Move.Rock && b == Move.Scissors) ||
            (a == Move.Paper && b == Move.Rock) ||
            (a == Move.Scissors && b == Move.Paper)
        ) return pa;

        return pb;
    }

    // ───────────── 6. Pull payments ─────────────

    /// @notice Withdraw any ether owed to the caller.
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

        emit Withdrawn(msg.sender, amount);
    }
}

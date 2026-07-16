// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract FairRockPaperScissors {
    // ───────────── Types ─────────────

    /// The three valid moves plus a sentinel `None` used as default.
    /// Solidity auto-rejects out-of-range enum values, so the validation
    /// burden is purely on `None`.
    enum Move {
        None,
        Rock,
        Paper,
        Scissors
    }

    /// Five-state machine. See the slide deck for the transition graph.
    enum Phase {
        Empty, // game id never created
        AwaitingP2, // P1 has staked; waiting for an opponent
        Committing, // both staked; waiting for both commits
        Revealing, // both committed; waiting for both reveals
        Settled // pot has been distributed (or refunded)
    }

    struct Game {
        address player1;
        address player2;
        uint256 stake; // per-player; pot = 2 * stake
        bytes32 commit1;
        bytes32 commit2;
        Move reveal1;
        Move reveal2;
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
    event Committed(
        uint256 indexed gameId,
        address indexed player,
        bytes32 commitHash
    );
    event Revealed(uint256 indexed gameId, address indexed player, Move move);
    event Settled(uint256 indexed gameId, address winner, uint256 payout);
    event Withdrawn(address indexed who, uint256 amount);

    // ───────────── Errors ─────────────

    error InvalidPhase();
    error WrongStake(uint256 sent, uint256 expected);
    error AlreadyCommitted();
    error CommitMismatch();
    error AlreadyRevealed();
    error NotPlayer();
    error InvalidMove();
    error SelfPlay();
    error ZeroStake();
    error NothingToWithdraw();
    error TransferFailed();

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
        g.phase = Phase.Committing;

        emit PlayerJoined(gameId, msg.sender);
    }

    /// @notice Cancel a game that has nobody joined yet. The creator gets
    ///         their stake back via the pull-payment queue.
    function cancelGame(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.AwaitingP2) revert InvalidPhase();
        if (msg.sender != g.player1) revert NotPlayer();

        pendingWithdrawals[g.player1] += g.stake;
        g.phase = Phase.Settled;
        emit Settled(gameId, address(0), 0);
    }

    // ───────────── 2. Commit phase ─────────────

    /// @notice Submit a binding commitment to a move.
    /// @param  commitHash  keccak256(abi.encodePacked(uint8(move), salt, msg.sender))
    function commit(uint256 gameId, bytes32 commitHash) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.Committing) revert InvalidPhase();

        if (msg.sender == g.player1) {
            if (g.commit1 != bytes32(0)) revert AlreadyCommitted();
            g.commit1 = commitHash;
        } else if (msg.sender == g.player2) {
            if (g.commit2 != bytes32(0)) revert AlreadyCommitted();
            g.commit2 = commitHash;
        } else {
            revert NotPlayer();
        }

        emit Committed(gameId, msg.sender, commitHash);

        // Both committed: open the reveal window.
        if (g.commit1 != bytes32(0) && g.commit2 != bytes32(0)) {
            g.phase = Phase.Revealing;
        }
    }

    // ───────────── 3. Reveal phase ─────────────

    /// @notice Reveal a previously committed move.
    /// @param  move  one of {Rock, Paper, Scissors} (Move.None is rejected).
    /// @param  salt  the random 32-byte value used in the commit hash.
    function reveal(uint256 gameId, Move move, bytes32 salt) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.Revealing) revert InvalidPhase();
        if (move == Move.None) revert InvalidMove();

        // Rehash with the *sender's* address; this is what defeats
        // commit-copying attacks (see contract-level NatSpec).
        bytes32 expected = keccak256(
            abi.encodePacked(uint8(move), salt, msg.sender)
        );

        if (msg.sender == g.player1) {
            if (g.reveal1 != Move.None) revert AlreadyRevealed();
            if (expected != g.commit1) revert CommitMismatch();
            g.reveal1 = move;
        } else if (msg.sender == g.player2) {
            if (g.reveal2 != Move.None) revert AlreadyRevealed();
            if (expected != g.commit2) revert CommitMismatch();
            g.reveal2 = move;
        } else {
            revert NotPlayer();
        }

        emit Revealed(gameId, msg.sender, move);

        // Both revealed: settle immediately. _settle only writes storage,
        // it does NOT make external calls — so this is safe.
        if (g.reveal1 != Move.None && g.reveal2 != Move.None) {
            _settle(gameId);
        }
    }

    // ───────────── 4. Settlement ─────────────

    function _settle(uint256 gameId) internal {
        Game storage g = games[gameId];
        address winner = _winner(g.reveal1, g.reveal2, g.player1, g.player2);
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

    // ───────────── 7. Off-chain helper ─────────────

    /// @notice Convenience helper to compute a commit hash off-chain.
    /// @dev    Same encoding the contract uses internally — pure function,
    ///         safe to call without sending a transaction. Use it from
    ///         JavaScript when testing in Remix, or replicate the encoding
    ///         in ethers.js with `ethers.solidityPackedKeccak256`.
    function makeCommitment(
        Move move,
        bytes32 salt,
        address player
    ) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(uint8(move), salt, player));
    }
}

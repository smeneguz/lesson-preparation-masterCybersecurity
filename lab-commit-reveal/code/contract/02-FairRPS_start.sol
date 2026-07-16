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
    function createGame() external payable returns (uint256 gameId) {}

    /// @notice Join an open game, matching the creator's stake.
    function joinGame(uint256 gameId) external payable {}

    /// @notice Cancel a game that has nobody joined yet. The creator gets
    ///         their stake back via the pull-payment queue.
    function cancelGame(uint256 gameId) external {}

    // ───────────── 2. Commit phase ─────────────

    /// @notice Submit a binding commitment to a move.
    /// @param  commitHash  keccak256(abi.encodePacked(uint8(move), salt, msg.sender))
    function commit(uint256 gameId, bytes32 commitHash) external {}

    // ───────────── 3. Reveal phase ─────────────

    /// @notice Reveal a previously committed move.
    /// @param  move  one of {Rock, Paper, Scissors} (Move.None is rejected).
    /// @param  salt  the random 32-byte value used in the commit hash.
    function reveal(uint256 gameId, Move move, bytes32 salt) external {}

    // ───────────── 4. Settlement ─────────────

    function _settle(uint256 gameId) internal {}

    /// @dev Returns the winning address, or `address(0)` on a draw.
    function _winner(
        Move a,
        Move b,
        address pa,
        address pb
    ) internal pure returns (address) {}

    // ───────────── 6. Pull payments ─────────────

    /// @notice Withdraw any ether owed to the caller.
    /// @dev    Safe without ReentrancyGuard: the balance is zeroed
    ///         BEFORE the external call (Checks-Effects-Interactions).
    function withdraw() external {}

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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  Rock-Paper-Scissors with a commit/reveal scheme  —  zero external imports.
//
//  PROTOCOL
//    1.  Player 1 creates a game with a stake.
//    2.  Player 2 joins by matching the stake.
//    3.  Both players COMMIT a hash of (move, salt, address).
//    4.  Both players REVEAL (move, salt). The contract recomputes the hash
//        and accepts the reveal iff it matches the previous commit.
//    5.  Once both reveals are in, the contract settles the pot.
//
//  TIMEOUTS
//    - If only one player commits, the other can be timed out and the
//      committer takes the pot.
//    - If only one player reveals, the same rule applies during the reveal
//      phase: the revealer wins.
//    - If nobody commits / reveals, both players get refunded their stake.
//
//  WHY THE HASH INCLUDES THE PLAYER ADDRESS
//    Without it, player 2 could copy player 1's commit hash bit-for-bit.
//    Later, when player 1 reveals (move, salt), player 2 would replay the
//    same (move, salt) — forcing a draw and a guaranteed split of the pot.
//    Hashing in msg.sender makes each commit unique to its author.
//
//  PULL PAYMENTS
//    Payouts go to `pendingWithdrawals`; winners (and refunded players) call
//    `withdraw()` to collect. This isolates the trust boundary: a malicious
//    receive() in a smart-contract winner can no longer block settlement
//    for the other player.
//
//  WHY NO ReentrancyGuard?
//    Both state-mutating paths that perform an external call already follow
//    the Checks-Effects-Interactions discipline:
//      • `reveal()` makes NO external call. It updates storage and may
//        trigger `_settle()`, which again only updates storage. Safe.
//      • `withdraw()` zeroes `pendingWithdrawals[msg.sender]` BEFORE the
//        low-level call. A re-entrant call from the recipient finds a
//        zero balance and reverts at the `NothingToWithdraw` check.
//    Adding a guard would be redundant and would cost an extra ~6 000 gas
//    per call without any security benefit on this contract.
// ─────────────────────────────────────────────────────────────────────────────

contract TimedFairRockPaperScissors {
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
        uint64 commitDeadline;
        uint64 revealDeadline;
        Phase phase;
    }

    // ───────────── Storage ─────────────

    uint256 public nextGameId;
    mapping(uint256 => Game) public games;
    mapping(address => uint256) public pendingWithdrawals;

    /// Two simple time windows. Choose values that comfortably exceed a
    /// transaction confirmation window — one hour is generous on Sepolia
    /// and even on mainnet during congestion.
    uint64 public constant COMMIT_WINDOW = 1 hours;
    uint64 public constant REVEAL_WINDOW = 1 hours;

    // ───────────── Events ─────────────

    event GameCreated(
        uint256 indexed gameId,
        address indexed player1,
        uint256 stake
    );
    event PlayerJoined(
        uint256 indexed gameId,
        address indexed player2,
        uint64 commitDeadline
    );
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
    error CommitDeadlineNotReached();
    error CommitDeadlinePassed();
    error RevealDeadlineNotReached();
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
        g.commitDeadline = uint64(block.timestamp + COMMIT_WINDOW);

        emit PlayerJoined(gameId, msg.sender, g.commitDeadline);
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
        if (block.timestamp > g.commitDeadline) revert CommitDeadlinePassed();

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
            g.revealDeadline = uint64(block.timestamp + REVEAL_WINDOW);
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

    // ───────────── 5. Timeout handlers ─────────────

    /// @notice Anyone can call this once the commit deadline has passed.
    ///         Distributes the pot according to who managed to commit.
    function claimCommitTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.Committing) revert InvalidPhase();
        if (block.timestamp <= g.commitDeadline)
            revert CommitDeadlineNotReached();

        bool p1Committed = g.commit1 != bytes32(0);
        bool p2Committed = g.commit2 != bytes32(0);
        uint256 pot = g.stake * 2;

        if (p1Committed && !p2Committed) {
            pendingWithdrawals[g.player1] += pot;
            emit Settled(gameId, g.player1, pot);
        } else if (!p1Committed && p2Committed) {
            pendingWithdrawals[g.player2] += pot;
            emit Settled(gameId, g.player2, pot);
        } else if (!p1Committed && !p2Committed) {
            // Neither played — full refund to both.
            pendingWithdrawals[g.player1] += g.stake;
            pendingWithdrawals[g.player2] += g.stake;
            emit Settled(gameId, address(0), 0);
        } else {
            // Both committed — the phase transition would have already moved
            // us out of Committing. Defensive revert.
            revert InvalidPhase();
        }

        g.phase = Phase.Settled;
    }

    /// @notice Anyone can call this once the reveal deadline has passed.
    ///         Distributes the pot according to who revealed.
    function claimRevealTimeout(uint256 gameId) external {
        Game storage g = games[gameId];
        if (g.phase != Phase.Revealing) revert InvalidPhase();
        if (block.timestamp <= g.revealDeadline)
            revert RevealDeadlineNotReached();

        bool p1Revealed = g.reveal1 != Move.None;
        bool p2Revealed = g.reveal2 != Move.None;
        uint256 pot = g.stake * 2;

        if (p1Revealed && !p2Revealed) {
            pendingWithdrawals[g.player1] += pot;
            emit Settled(gameId, g.player1, pot);
        } else if (!p1Revealed && p2Revealed) {
            pendingWithdrawals[g.player2] += pot;
            emit Settled(gameId, g.player2, pot);
        } else if (!p1Revealed && !p2Revealed) {
            // Both vanished — refund.
            pendingWithdrawals[g.player1] += g.stake;
            pendingWithdrawals[g.player2] += g.stake;
            emit Settled(gameId, address(0), 0);
        } else {
            revert InvalidPhase();
        }

        g.phase = Phase.Settled;
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — DAO · Token-weighted governance over a treasury (the SOLUTION)
//
//  A minimal but complete governance flow:
//    propose → vote (weighted by governance-token balance) → timelock → execute
//
//  The DAO contract IS the treasury: it holds ETH, and a passed proposal makes
//  the DAO perform an arbitrary call (e.g. pay an address, call another
//  contract). Execution follows Checks-Effects-Interactions: `executed` is set
//  BEFORE the external call, so a proposal can never be run twice or re-entered.
//
//  ── IMPORTANT teaching simplification ────────────────────────────────────────
//  Voting weight here is `token.balanceOf(voter)` read AT VOTE TIME. This is
//  simple but VULNERABLE: a voter could flash-borrow governance tokens, vote,
//  and return them in the same transaction (this is exactly the Beanstalk 2022
//  attack, ~$182M). Production DAOs snapshot voting power at the proposal's
//  creation block using checkpointed balances (OpenZeppelin `ERC20Votes` +
//  `Governor`). See the README extension.
//
//  PROVA RAPIDA (Remix VM; usa 3 account A, B, C dal menu "Account"; 18 decimali):
//   1) Account A: deploy GovToken(1000000000000000000000)             // 1000 GOV ad A
//   2) Account A: sul token, transfer(B, 400000000000000000000)       // 400 GOV a B
//                 sul token, transfer(C, 100000000000000000000)       // 100 GOV a C  (ad A restano 500)
//   3) Account A: deploy SimpleDAO(
//         <indirizzo GovToken>,
//         300000000000000000000,   // quorum = 300 GOV
//         60,                       // votingPeriod = 60 secondi (per provare in aula)
//         0)                        // timelockDelay = 0
//   4) Finanzia la tesoreria: in alto imposta VALUE = 5 ether, poi in basso al
//      contratto SimpleDAO usa "Low level interactions" (CALLDATA vuoto) -> Transact.
//      Verifica treasuryBalance() = 5000000000000000000.  (Rimetti poi VALUE a 0.)
//   5) Account A: propose(
//         <indirizzo di C>,         // target = chi riceve
//         1000000000000000000,      // value = 1 ETH (in wei) dalla tesoreria; propose NON e' payable
//         0x,                       // data vuoto = semplice invio di ETH
//         "Pay grant to C")
//      >> Il PRIMO proposalId e' 1 (non 0). Leggilo in proposalCount() o nell'evento.
//   6) Vota (id = 1): A -> vote(1, true)  [peso 500];  C -> vote(1, true) [100];
//                     B -> vote(1, false) [400].    Totale: for = 600, against = 400.
//   7) Aspetta ~60 secondi reali, poi (qualsiasi account) execute(1).
//      Passa (600 > 400 e 600 >= 300): la DAO invia 1 ETH a C.
//      Verifica treasuryBalance() = 4000000000000000000; execute(1) di nuovo -> AlreadyExecuted.
//   Da provare: execute prima dei 60s -> VotingOngoing; solo C vota si -> ProposalRejected.
// ─────────────────────────────────────────────────────────────────────────────

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

/// @title A tiny governance token (18 decimals). Full supply to the deployer,
///        who distributes voting power by transferring tokens to members.
contract GovToken is IERC20 {
    string public constant name = "Gov Token";
    string public constant symbol = "GOV";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(uint256 initialSupply) {
        totalSupply = initialSupply;
        balanceOf[msg.sender] = initialSupply;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "allowance");
        require(balanceOf[from] >= amount, "insufficient");
        if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @title Minimal token-weighted DAO with a timelock.
contract SimpleDAO {
    IERC20 public immutable token;

    /// @notice How long voting stays open after a proposal is created (seconds).
    /// @dev    Real DAOs use days; for a Remix classroom run pass something
    ///         small (e.g. 60) so you can wait it out live.
    uint256 public immutable votingPeriod;
    /// @notice Delay between voting close and earliest execution — the timelock
    ///         (seconds). Pass 0 for a quick demo; real DAOs use ~1-2 days.
    uint256 public immutable timelockDelay;
    /// @notice Minimum total FOR votes required for a proposal to pass.
    uint256 public immutable quorumVotes;

    struct Proposal {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        uint256 endTime; // voting closes at this time
        uint256 eta; // earliest execution time (endTime + TIMELOCK_DELAY)
        uint256 forVotes;
        uint256 againstVotes;
        bool executed;
    }

    uint256 public proposalCount;
    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(address => bool)) public hasVoted;

    event ProposalCreated(uint256 indexed id, address indexed proposer, address target, uint256 value, string description);
    event Voted(uint256 indexed id, address indexed voter, bool support, uint256 weight);
    event Executed(uint256 indexed id, bool success);

    error NoVotingPower();
    error VotingClosed();
    error VotingOngoing();
    error AlreadyVoted();
    error AlreadyExecuted();
    error TimelockNotElapsed();
    error ProposalRejected();
    error CallFailed();

    constructor(
        address governanceToken,
        uint256 _quorumVotes,
        uint256 _votingPeriod,
        uint256 _timelockDelay
    ) {
        token = IERC20(governanceToken);
        quorumVotes = _quorumVotes;
        votingPeriod = _votingPeriod;
        timelockDelay = _timelockDelay;
    }

    /// @notice Let the DAO receive ETH into its treasury.
    receive() external payable {}

    // ───────────── Propose ─────────────

    /// @notice Create a proposal to make the DAO call `target` with `data`,
    ///         forwarding `value` wei from the treasury.
    function propose(
        address target,
        uint256 value,
        bytes calldata data,
        string calldata description
    ) external returns (uint256 id) {
        if (token.balanceOf(msg.sender) == 0) revert NoVotingPower();

        id = ++proposalCount;
        Proposal storage p = proposals[id];
        p.proposer = msg.sender;
        p.target = target;
        p.value = value;
        p.data = data;
        p.endTime = block.timestamp + votingPeriod;
        p.eta = p.endTime + timelockDelay;

        emit ProposalCreated(id, msg.sender, target, value, description);
    }

    // ───────────── Vote ─────────────

    /// @notice Cast a weighted vote. Weight = your governance-token balance now.
    function vote(uint256 id, bool support) external {
        Proposal storage p = proposals[id];
        if (block.timestamp > p.endTime) revert VotingClosed();
        if (hasVoted[id][msg.sender]) revert AlreadyVoted();

        uint256 weight = token.balanceOf(msg.sender);
        if (weight == 0) revert NoVotingPower();

        hasVoted[id][msg.sender] = true;
        if (support) {
            p.forVotes += weight;
        } else {
            p.againstVotes += weight;
        }

        emit Voted(id, msg.sender, support, weight);
    }

    // ───────────── Execute ─────────────

    /// @notice Execute a passed proposal after the timelock.
    /// @dev    A proposal PASSES iff voting has closed, forVotes > againstVotes,
    ///         and forVotes >= quorumVotes. CEI: `executed` is set before the call.
    function execute(uint256 id) external returns (bool success) {
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp <= p.endTime) revert VotingOngoing();
        if (block.timestamp < p.eta) revert TimelockNotElapsed();

        bool passed = p.forVotes > p.againstVotes && p.forVotes >= quorumVotes;
        if (!passed) revert ProposalRejected();

        p.executed = true; // EFFECT before INTERACTION

        (success, ) = p.target.call{value: p.value}(p.data);
        if (!success) revert CallFailed();

        emit Executed(id, success);
    }

    // ───────────── View ─────────────

    function treasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

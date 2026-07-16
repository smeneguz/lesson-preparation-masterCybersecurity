// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — DAO · Token-weighted governance over a treasury (YOUR TASK)
//
//  Complete the governance logic:
//    • vote     — weight a vote by the caller's governance-token balance,
//                 block double-voting and votes after the deadline.
//    • execute  — decide whether a proposal PASSED (majority + quorum) and,
//                 if so, run the DAO's call following Checks-Effects-Interactions.
//
//  The rest (propose, storage, timelock timing) is provided. See the README.
//
//  Teaching note: weight = balanceOf at vote time is intentionally SIMPLE and
//  intentionally VULNERABLE to flash-loan vote-buying (Beanstalk, 2022). The
//  production fix — snapshotting voting power at proposal creation — is the
//  README extension.
// ─────────────────────────────────────────────────────────────────────────────

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
}

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

contract SimpleDAO {
    IERC20 public immutable token;

    uint256 public immutable votingPeriod;
    uint256 public immutable timelockDelay;
    uint256 public immutable quorumVotes;

    struct Proposal {
        address proposer;
        address target;
        uint256 value;
        bytes data;
        uint256 endTime;
        uint256 eta;
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

    receive() external payable {}

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

    /// @notice Cast a weighted vote.
    /// @dev    TODO 1: implement voting.
    ///           1. revert VotingClosed() if block.timestamp > p.endTime.
    ///           2. revert AlreadyVoted() if hasVoted[id][msg.sender].
    ///           3. weight = token.balanceOf(msg.sender); revert NoVotingPower() if 0.
    ///           4. mark hasVoted; add weight to p.forVotes or p.againstVotes.
    ///           5. emit Voted.
    function vote(uint256 id, bool support) external {
        Proposal storage p = proposals[id];
        // TODO 1
        p;
        support;
    }

    /// @notice Execute a passed proposal after the timelock.
    /// @dev    TODO 2: replace the `passed` line. A proposal PASSES iff:
    ///           forVotes > againstVotes   AND   forVotes >= quorumVotes.
    ///         Keep the CEI ordering: set p.executed = true BEFORE the call.
    function execute(uint256 id) external returns (bool success) {
        Proposal storage p = proposals[id];
        if (p.executed) revert AlreadyExecuted();
        if (block.timestamp <= p.endTime) revert VotingOngoing();
        if (block.timestamp < p.eta) revert TimelockNotElapsed();

        bool passed = false; // TODO 2: compute the real pass condition.
        if (!passed) revert ProposalRejected();

        p.executed = true; // EFFECT before INTERACTION

        (success, ) = p.target.call{value: p.value}(p.data);
        if (!success) revert CallFailed();

        emit Executed(id, success);
    }

    function treasuryBalance() external view returns (uint256) {
        return address(this).balance;
    }
}

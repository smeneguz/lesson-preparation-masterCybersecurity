// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Oracles · Consuming a price feed safely (YOUR TASK)
//
//  Same mock feed as file 01. Your job: complete `getSafePrice` so it REJECTS
//  bad data instead of returning it. A price feed can fail in three ways your
//  contract must defend against:
//
//    1) Non-positive answer     — a bug/misconfig can report 0 or a negative
//                                 value; never treat that as a price.
//    2) Stale answer            — the feed stopped updating (node outage, a
//                                 depegged pair). Reject if it is older than a
//                                 maximum age you choose.
//    3) Incomplete round        — updatedAt == 0 means the round never closed.
//
//  Complete the four TODOs, then test with the scenarios in the README.
// ─────────────────────────────────────────────────────────────────────────────

interface AggregatorV3Interface {
    function decimals() external view returns (uint8);
    function description() external view returns (string memory);
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 public immutable decimalsValue;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;

    constructor(uint8 _decimals, int256 _initialAnswer) {
        decimalsValue = _decimals;
        _push(_initialAnswer, block.timestamp);
    }

    function decimals() external view returns (uint8) {
        return decimalsValue;
    }

    function description() external pure returns (string memory) {
        return "MOCK / USD";
    }

    function updateAnswer(int256 _answer) external {
        _push(_answer, block.timestamp);
    }

    function updateAnswerWithTimestamp(int256 _answer, uint256 _updatedAt)
        external
    {
        _push(_answer, _updatedAt);
    }

    function _push(int256 _answer, uint256 _updatedAt) internal {
        answer = _answer;
        updatedAt = _updatedAt;
        roundId += 1;
    }

    function latestRoundData()
        external
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }
}

/// @title A safe price consumer — complete the checks.
contract SafePriceConsumer {
    AggregatorV3Interface public immutable feed;

    /// @notice Reject any answer older than this many seconds.
    ///         Real feeds publish a "heartbeat" (e.g. 3600s); pick a bound at
    ///         or slightly above it.
    uint256 public constant MAX_STALENESS = 3600;

    error NonPositivePrice(int256 answer);
    error StalePrice(uint256 updatedAt, uint256 nowTs);
    error IncompleteRound();

    constructor(address feedAddress) {
        feed = AggregatorV3Interface(feedAddress);
    }

    /// @notice Return the latest price ONLY if it passes every sanity check.
    /// @return price the validated answer (feed decimals; USD pairs = 8).
    function getSafePrice() external view returns (int256 price) {
        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = feed.latestRoundData();

        // TODO 1: revert IncompleteRound() if `updatedAt` is 0.

        // TODO 2: revert NonPositivePrice(answer) if `answer` is not > 0.

        // TODO 3: revert StalePrice(updatedAt, block.timestamp) if the answer
        //         is older than MAX_STALENESS seconds
        //         (i.e. block.timestamp - updatedAt > MAX_STALENESS).

        // TODO 4: return the validated `answer`.
    }
}

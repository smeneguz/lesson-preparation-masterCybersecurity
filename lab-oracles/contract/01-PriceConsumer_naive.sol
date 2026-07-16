// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Oracles · Consuming a price feed (the NAIVE version)
//
//  This file is COMPLETE and meant to be RUN. It shows what goes wrong when a
//  contract trusts an oracle's answer WITHOUT validating it.
//
//  It uses the real Chainlink `AggregatorV3Interface` shape, plus a local mock
//  aggregator you can drive by hand — so everything runs in the Remix VM with
//  no network. The mock lets you push a stale, zero, or negative "price"; the
//  naive consumer returns it blindly. In a lending market that value would
//  decide who gets liquidated.
//
//  Fix it in 02-PriceConsumer_start.sol.
// ─────────────────────────────────────────────────────────────────────────────

/// @notice The standard Chainlink data-feed interface (subset actually used).
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

/// @title A hand-drivable mock of a Chainlink aggregator.
/// @notice NOT a real oracle — a teaching stand-in. In production the address
///         you pass to the consumer is a live Chainlink feed (e.g. ETH/USD).
contract MockV3Aggregator is AggregatorV3Interface {
    uint8 public immutable decimalsValue;
    int256 public answer;
    uint256 public updatedAt;
    uint80 public roundId;

    /// @param _decimals how many decimals the feed reports (USD pairs use 8).
    /// @param _initialAnswer the starting price, scaled by 10**_decimals.
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

    /// @notice Publish a fresh price (updatedAt = now). Simulates a healthy feed.
    function updateAnswer(int256 _answer) external {
        _push(_answer, block.timestamp);
    }

    /// @notice Publish a price with an ARBITRARY timestamp — use this to
    ///         simulate a STALE feed (e.g. pass updatedAt = 1).
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
        // startedAt is reported equal to updatedAt for simplicity;
        // answeredInRound == roundId (single-round mock).
        return (roundId, answer, updatedAt, updatedAt, roundId);
    }
}

/// @title A consumer that trusts the feed blindly — DO NOT COPY.
contract NaivePriceConsumer {
    AggregatorV3Interface public immutable feed;

    constructor(address feedAddress) {
        feed = AggregatorV3Interface(feedAddress);
    }

    /// @notice Returns whatever the feed last reported — no checks at all.
    /// @dev    Try it after calling `updateAnswerWithTimestamp(-5, 1)` on the
    ///         mock: this happily returns a NEGATIVE, ANCIENT price.
    function getPrice() external view returns (int256) {
        (, int256 price, , , ) = feed.latestRoundData();
        return price; // <-- no positivity check, no freshness check
    }
}

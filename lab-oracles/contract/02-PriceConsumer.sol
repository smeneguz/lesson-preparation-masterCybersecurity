// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
//  LAB — Oracles · Consuming a price feed safely (the SOLUTION)
//
//  `getSafePrice` validates the answer before returning it:
//    • the round must be complete (updatedAt != 0),
//    • the price must be strictly positive,
//    • the price must be fresh (not older than MAX_STALENESS).
//
//  This mirrors the slide "In practice: consuming a price feed (Chainlink)".
//  Against a live deployment you would pass a real feed address (e.g. the
//  ETH/USD aggregator) instead of the mock.
//
//  PROVA RAPIDA (Remix): deploy `MockV3Aggregator(8, 200000000000)`, poi
//  `SafePriceConsumer(<indirizzo del mock>)`. Chiama `getSafePrice()` sul
//  consumer -> 200000000000 (=2000,00$). Poi sul mock chiama
//  `updateAnswer(0)` -> `getSafePrice()` reverte `NonPositivePrice`; oppure
//  `updateAnswerWithTimestamp(200000000000, 1)` -> reverte `StalePrice`.
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

/// @title A safe price consumer.
contract SafePriceConsumer {
    AggregatorV3Interface public immutable feed;

    uint256 public constant MAX_STALENESS = 3600;

    error NonPositivePrice(int256 answer);
    error StalePrice(uint256 updatedAt, uint256 nowTs);
    error IncompleteRound();

    constructor(address feedAddress) {
        feed = AggregatorV3Interface(feedAddress);
    }

    /// @notice Return the latest price ONLY if it passes every sanity check.
    function getSafePrice() external view returns (int256 price) {
        (
            ,
            int256 answer,
            ,
            uint256 updatedAt,

        ) = feed.latestRoundData();

        if (updatedAt == 0) revert IncompleteRound();
        if (answer <= 0) revert NonPositivePrice(answer);
        if (block.timestamp - updatedAt > MAX_STALENESS) {
            revert StalePrice(updatedAt, block.timestamp);
        }

        return answer;
    }
}

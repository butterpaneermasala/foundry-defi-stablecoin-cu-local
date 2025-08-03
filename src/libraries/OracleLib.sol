//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title OracleLib
 * @author Satya Pradhan
 * @notice This library is used to check the Chainlink Oracle for stale data.
 * If a price is stale, functions will revert, and render the DSCEngine unusable - this is by design.
 * We want the DSCEngine to freeze if prices become stale.
 *
 * So if the Chainlink network explodes and you have a lot of money locked in the protocol... too bad.
 */
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours;

    function staleCheckLatestRoundData(AggregatorV3Interface pricefeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            pricefeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) revert OracleLib__StalePrice();

        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function getUsdValue(
        AggregatorV3Interface priceFeed,
        uint256 amount,
        uint256 additionalFeedPrecision,
        uint256 precision
    ) public view returns (uint256) {
        (, int256 price,,,) = staleCheckLatestRoundData(priceFeed);
        // 1 ETH = 1000 USD
        // The returned value from Chainlink will be 1000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        // We want to have everything in terms of WEI, so we add 10 zeros at the end
        return ((uint256(price) * additionalFeedPrecision) * amount) / precision;
    }

    function getTokenAmountFromUsd(
        AggregatorV3Interface priceFeed,
        uint256 usdAmountInWei,
        uint256 additionalFeedPrecision,
        uint256 precision
    ) public view returns (uint256) {
        (, int256 price,,,) = staleCheckLatestRoundData(priceFeed);
        // $100e18 USD Debt
        // 1 ETH = 2000 USD
        // The returned value from Chainlink will be 2000 * 1e8
        // Most USD pairs have 8 decimals, so we will just pretend they all do
        return ((usdAmountInWei * precision) / (uint256(price) * additionalFeedPrecision));
    }
}

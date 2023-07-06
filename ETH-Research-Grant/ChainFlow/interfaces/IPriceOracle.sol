// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IPriceOracle {
    function initialize(address _uniSwapRouter) external;

    function getDecimal(address tokenAddress) external view returns (uint256);

    function getTokenPrice(address token_address, address token1_address)
        external
        view
        returns (uint256);
}

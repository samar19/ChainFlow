// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4 || ^0.7.6 || ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IPriceOracle.sol";
import "../core/IndexSwap.sol";

contract IndexSwapLibrary {
    IPriceOracle oracle;
    address wETH;

    using SafeMath for uint256;

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");

    function initialize(address _oracle, address _weth) external {
        oracle = IPriceOracle(_oracle);
        wETH = _weth;
    }

    /**
     * @notice The function calculates the balance of each token in the vault and converts them to BNB and 
               the sum of those values which represents the total vault value in BNB
     * @return tokenXBalance A list of the value of each token in the portfolio in BNB
     * @return vaultValue The total vault value in BNB
     */
    function getTokenAndVaultBalance(IndexSwap _index)
        public
        view
        returns (uint256[] memory tokenXBalance, uint256 vaultValue)
    {
        uint256[] memory tokenBalanceInBNB = new uint256[](
            _index.getTokens().length
        );
        uint256 vaultBalance = 0;

        if (_index.totalSupply() > 0) {
            for (uint256 i = 0; i < _index.getTokens().length; i++) {
                uint256 tokenBalance = IERC20(_index.getTokens()[i]).balanceOf(
                    _index.vault()
                );
                uint256 tokenBalanceBNB;

                tokenBalanceBNB = _getTokenAmountInBNB(
                    _index,
                    _index.getTokens()[i],
                    tokenBalance
                );

                tokenBalanceInBNB[i] = tokenBalanceBNB;
                vaultBalance = vaultBalance.add(tokenBalanceBNB);

                require(vaultBalance > 0, "sum price is not greater than 0");
            }
            return (tokenBalanceInBNB, vaultBalance);
        } else {
            return (new uint256[](0), 0);
        }
    }

    /**
     * @notice The function calculates the amount in BNB to swap from BNB to each token
     * @dev The amount for each token has to be calculated to ensure the ratio (weight in the portfolio) stays constant
     * @param tokenAmount The amount a user invests into the portfolio
     * @param tokenBalanceInBNB The balanace of each token in the portfolio converted to BNB
     * @param vaultBalance The total vault value of all tokens converted to BNB
     * @return A list of amounts that are being swapped into the portfolio tokens
     */
    function calculateSwapAmounts(
        IndexSwap _index,
        uint256 tokenAmount,
        uint256[] memory tokenBalanceInBNB,
        uint256 vaultBalance
    ) public view returns (uint256[] memory) {
        uint256[] memory amount = new uint256[](_index.getTokens().length);
        if (_index.totalSupply() > 0) {
            for (uint256 i = 0; i < _index.getTokens().length; i++) {
                amount[i] = tokenBalanceInBNB[i].mul(tokenAmount).div(
                    vaultBalance
                );
            }
        }
        return amount;
    }

    /**
     * @notice The function converts the given token amount into BNB
     * @param t The base token being converted to BNNB
     * @param amount The amount to convert to BNB
     * @return amountInBNB The converted BNB amount
     */
    function _getTokenAmountInBNB(
        IndexSwap _index,
        address t,
        uint256 amount
    ) public view returns (uint256 amountInBNB) {
        if (t == wETH) {
            return amount;
        }

        uint256 decimal = oracle.getDecimal(t);
        uint256 tokenPrice = oracle.getTokenPrice(t, _index.outAsset());
        amountInBNB = tokenPrice.mul(amount).div(10**decimal);
    }
}

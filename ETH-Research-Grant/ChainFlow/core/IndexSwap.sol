// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4 || ^0.7.6 || ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IWETH.sol";
import "./IndexSwapLibrary.sol";
import "./IndexManager.sol";
import "../access/AccessController.sol";

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TokenBase is
    Initializable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    function __TokenBase_init(string memory _name, string memory _symbol)
        internal
        initializer
    {
        __ERC20_init(_name, _symbol);
        __ERC20Burnable_init();
        __Ownable_init();
        __ReentrancyGuard_init();
    }
}

contract IndexSwap is TokenBase {
    // IERC20 public token;
    using SafeMath for uint256;

    uint256 public indexPrice;

    address public vault;

    /**
     * @dev Token record data structure
     * @param lastDenormUpdate timestamp of last denorm change
     * @param denorm denormalized weight
     * @param index index of address in tokens array
     */
    struct Record {
        uint40 lastDenormUpdate;
        uint96 denorm;
        uint8 index;
    }
    // Array of underlying tokens in the pool.
    address[] internal _tokens;

    // Internal records of the pool's underlying tokens
    mapping(address => Record) internal _records;

    // Total denormalized weight of the pool.
    uint256 public constant TOTAL_WEIGHT = 10_000;

    // Total denormalized weight of the pool.
    uint256 internal MAX_INVESTMENTAMOUNT;

    address public outAsset;
    IndexSwapLibrary public indexSwapLibrary;
    IndexManager public indexManager;
    AccessController public accessController;

    bytes32 public constant DEFAULT_ADMIN_ROLE =
        keccak256("DEFAULT_ADMIN_ROLE");

    bytes32 public constant ASSET_MANAGER_ROLE =
        keccak256("ASSET_MANAGER_ROLE");

    bytes32 public constant INDEX_MANAGER_ROLE =
        keccak256("INDEX_MANAGER_ROLE");

    function initialize(
        string memory _name,
        string memory _symbol,
        address _outAsset,
        address _vault,
        uint256 _maxInvestmentAmount,
        IndexSwapLibrary _indexSwapLibrary,
        IndexManager _indexManager,
        AccessController _accessController
    ) public {
        __TokenBase_init(_name, _symbol);

        vault = _vault;
        outAsset = _outAsset; //As now we are tacking busd
        MAX_INVESTMENTAMOUNT = _maxInvestmentAmount;
        indexSwapLibrary = IndexSwapLibrary(_indexSwapLibrary);
        indexManager = IndexManager(_indexManager);
        accessController = _accessController;

        // OpenZeppelin Access Control
        accessController.setRoleAdmin(INDEX_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        accessController.setupRole(INDEX_MANAGER_ROLE, address(this));
    }

    /** @dev Emitted when public trades are enabled. */
    event LOG_PUBLIC_SWAP_ENABLED();

    /**
     * @dev Sets up the initial assets for the pool.
     * @param tokens Underlying tokens to initialize the pool with
     * @param denorms Initial denormalized weights for the tokens
     */
    function init(address[] calldata tokens, uint96[] calldata denorms)
        external
        onlyOwner
    {
        require(_tokens.length == 0, "INITIALIZED");
        uint256 len = tokens.length;
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < len; i++) {
            _records[tokens[i]] = Record({
                lastDenormUpdate: uint40(block.timestamp),
                denorm: denorms[i],
                index: uint8(i)
            });
            _tokens.push(tokens[i]);

            totalWeight = totalWeight.add(denorms[i]);
        }
        require(totalWeight == TOTAL_WEIGHT, "INVALID_WEIGHTS");

        emit LOG_PUBLIC_SWAP_ENABLED();
    }

    /**
     * @notice The function calculates the amount of index tokens the user can buy/mint with the invested amount.
     * @param _amount The invested amount after swapping ETH into portfolio tokens converted to BNB to avoid 
                      slippage errors
     * @param sumPrice The total value in the vault converted to BNB
     * @return Returns the amount of index tokens to be minted.
     */
    function _mintShareAmount(uint256 _amount, uint256 sumPrice)
        internal
        view
        returns (uint256)
    {
        uint256 indexTokenSupply = totalSupply();

        return _amount.mul(indexTokenSupply).div(sumPrice);
    }

    /**
     * @notice The function swaps BNB into the portfolio tokens after a user makes an investment
     * @dev The output of the swap is converted into BNB to get the actual amount after slippage to calculate 
            the index token amount to mint
     * @dev (tokenBalanceInBNB, vaultBalance) has to be calculated before swapping for the _mintShareAmount function 
            because during the swap the amount will change but the index token balance is still the same 
            (before minting)
     */
    function investInFund(address user) public payable nonReentrant {
        uint256 tokenAmount = msg.value;
        require(_tokens.length != 0, "NOT INITIALIZED");
        require(
            tokenAmount <= MAX_INVESTMENTAMOUNT,
            "Amount exceeds maximum investment amount!"
        );
        uint256 investedAmountAfterSlippage = 0;
        uint256 vaultBalance = 0;
        uint256 len = _tokens.length;
        uint256[] memory amount = new uint256[](len);
        uint256[] memory tokenBalanceInBNB = new uint256[](len);

        (tokenBalanceInBNB, vaultBalance) = indexSwapLibrary
            .getTokenAndVaultBalance(this);

        amount = indexSwapLibrary.calculateSwapAmounts(
            this,
            tokenAmount,
            tokenBalanceInBNB,
            vaultBalance
        );

        investedAmountAfterSlippage = _swapETHToTokens(tokenAmount, amount);
        require(
            investedAmountAfterSlippage <= tokenAmount,
            "amount after slippage can't be greater than before"
        );
        if (totalSupply() > 0) {
            tokenAmount = _mintShareAmount(
                investedAmountAfterSlippage,
                vaultBalance
            );
        } else {
            tokenAmount = investedAmountAfterSlippage;
        }

        _mint(user, tokenAmount);

        // refund leftover ETH to user
        (bool success, ) = user.call{value: address(this).balance}("");
        require(success, "refund failed");
    }

    /**
     * @notice The function swaps ETH to the portfolio tokens
     * @param tokenAmount The amount being used to calculate the amount to swap for the first investment
     * @param amount A list of amounts specifying the amount of ETH to be swapped to each token in the portfolio
     * @return investedAmountAfterSlippage
     */
    function _swapETHToTokens(uint256 tokenAmount, uint256[] memory amount)
        internal
        returns (uint256 investedAmountAfterSlippage)
    {
        for (uint256 i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            Record memory record = _records[t];
            uint256 swapAmount;
            if (totalSupply() == 0) {
                swapAmount = tokenAmount.mul(record.denorm).div(TOTAL_WEIGHT);
            } else {
                swapAmount = amount[i];
            }

            require(address(this).balance >= swapAmount, "not enough bnb");

            uint256 swapResult = indexManager._swapETHToToken{
                value: swapAmount
            }(t, swapAmount, vault);

            investedAmountAfterSlippage = investedAmountAfterSlippage.add(
                indexSwapLibrary._getTokenAmountInBNB(this, t, swapResult)
            );
        }
    }


    function getTokens() public view returns (address[] memory) {
        return _tokens;
    }

    function getRecord(address _token) public view returns (Record memory) {
        return _records[_token];
    }

    // important to receive ETH
    receive() external payable {}
}

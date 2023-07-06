pragma solidity ^0.8.15;

import {IConnext} from "@connext/nxtp-contracts/contracts/core/connext/interfaces/IConnext.sol";
import {IXReceiver} from "@connext/nxtp-contracts/contracts/core/connext/interfaces/IXReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IUniswapV2Router02.sol";

import "./IIndexSwap.sol";
import "./IWETH.sol";


contract ReceiverIndex is IXReceiver {
  // Number of pings this contract has received from the Ping contract
  uint256 public pings;

  IIndexSwap publßic index;

  // The connext contract deployed on the same domain as this contract
  IConnext public immutable connext;

  IUniswapV2Router02 uniswapRouter;
  // work done

  constructor(IConnext _connext, IIndexSwap _index, address _router) {
    connext = _connext;
    index = _index;
    uniswapRouter = IUniswapV2Router02(_router);
  }

  /** 
   * @notice The receiver function as required by the IXReceiver interface.
   * @dev The Connext bridge contract will call this function.
   */
  function xReceive(
    bytes32 _transferId,
    uint256 _amount,
    address _asset,
    address _originSender,
    uint32 _origin,
    bytes memory _callData
  ) external returns (bytes memory) {
    // Because this call is *not* authenticated, the _originSender will be the Zero Address
    // Ping's address was sent with the xcall so it could be decoded and used for the nested xcall
    (address user) = abi.decode(_callData, (address));

    // weth balance
    IERC20 _token = IERC20(_asset);
    uint256 balance = _token.balanceOf(address(this));

    // swap to native token
    uniswapRouter.swapExactTokensForETH(
        balance,
        1,
        getPathForToken(_asset),
        address(this),
        block.timestamp
    )[1];

    index.investInFund{value: address(this).balance} (user);
    
  }

  function getPathForToken(address token)
        public
        view
        returns (address[] memory)
    {
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = uniswapRouter.WETH();
        return path;
    }
}
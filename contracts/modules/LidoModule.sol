// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import '@yield-protocol/vault-interfaces/IJoin.sol';
import '@yield-protocol/vault-interfaces/ICauldron.sol';
import '@yield-protocol/utils-v2/contracts/token/IERC20.sol';
import '@yield-protocol/utils-v2/contracts/token/TransferHelper.sol';
import '@yield-protocol/utils-v2/contracts/math/WMul.sol';
import '@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol';
import '@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol';
import '@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol';
import '../LadleStorage.sol';
import '../oracles/lido/IWstETH.sol';

/// @dev A ladle module to handle wrapping & unwrapping of stETH
contract LidoModule is LadleStorage {
    using WMul for uint256;
    using CastU256U128 for uint256;
    using CastU256I128 for uint256;
    using CastU128I128 for uint128;
    using TransferHelper for IERC20;
    using TransferHelper for IWstETH;
    using TransferHelper for IWETH9;
    using TransferHelper for address payable;
    IWstETH public wstETH;

    constructor(
        ICauldron cauldron,
        IWETH9 steth,
        IWstETH wstETH_
    ) LadleStorage(cauldron, steth) {
        wstETH = wstETH_;
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId) internal view returns (IJoin join) {
        join = joins[assetId];
        require(join != IJoin(address(0)), 'Join not found');
    }

    /// @dev Accept stEth, wrap it and forward it to the WstethJoin
    /// This function should be called first in a batch, and the Join should keep track of stored reserves
    /// Passing the id for a join that doesn't link to a contract implemnting IWETH9 will fail
    function joinStEth(bytes6 wstEthId) external returns (uint256 stEthTransferred) {
        stEthTransferred = weth.balanceOf(address(this));
        IJoin wstEthJoin = getJoin(wstEthId);
        uint256 wrappedAmount = wstETH.wrap(stEthTransferred);
        wstETH.safeTransfer(address(wstEthJoin), wrappedAmount);
    }

    /// @dev Unwrap WstETH held by this Ladle, and send the stETH
    /// This function should be called last in a batch, and the Ladle should have no reason to keep an WSTETH balance
    function exitStEth(address to) external returns (uint256 ethTransferred) {
        ethTransferred = wstETH.balanceOf(address(this));
        uint256 unwrappedAmount = wstETH.unwrap(ethTransferred);
        weth.safeTransfer(to, unwrappedAmount);
    }
}
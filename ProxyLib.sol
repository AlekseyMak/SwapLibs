// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../integrations/perpetual/IClearingHouse.sol";
import "../integrations/uniswap/IV3SwapRouter.sol";

library Perp {

    uint256 constant deadline = 300;
    uint32 constant hour = 3600;

    function deposit(address perpVault, address usdcToken, uint256 amountX10_D) external {
        require(amountX10_D != 0, "PL: zero amount");
        (bool success, bytes memory returnBytes) = usdcToken.call(
            abi.encodeWithSignature("approve(address,uint256)", perpVault, amountX10_D)
        );
        require(success, "PL: USDC approve failed");
        (bool successDeposit, bytes memory returnBytesDeposit) = perpVault.call(
            abi.encodeWithSignature("deposit(address,uint256)", usdcToken, amountX10_D)
        );
        require(successDeposit, "PL: deposit failed");
    }

    function withdraw(address perpVault, address usdcToken, uint256 amountX10_D) external {
        (bool success, bytes memory returnBytes) = perpVault.call(
            abi.encodeWithSignature("withdraw(address,uint256)", usdcToken, amountX10_D)
        );
        require(success, "PL: withdraw failed");
    }

    function withdrawAll(address perpVault, address usdcToken) external {
        (bool success, bytes memory returnBytes) = perpVault.call(
            abi.encodeWithSignature("getFreeCollateral(address)", address(this))
        );
        require(success, "PL: Failed to fetch collateral info");
        uint256 freeCollateral = abi.decode(returnBytes, (uint256));
        (bool successWithdraw, bytes memory returnBytesWithdraw) = perpVault.call(
            abi.encodeWithSignature("withdraw(address,uint256)", usdcToken, freeCollateral)
        );
        require(successWithdraw, "PL: withdraw all failed");
    }

    function openPosition(address clearingHouse,
        address vToken,
        bool positionType,
        uint256 amount,
        bytes32 referralCode) external {
        IClearingHouse(clearingHouse).openPosition(
            IClearingHouse.OpenPositionParams({
                baseToken : vToken,
                isBaseToQuote : positionType, //true for shorting the baseTokenAsset, false for long the baseTokenAsset
                isExactInput : false, // for specifying exactInput or exactOutput ; similar to UniSwap V2's specs
                amount : amount, // Depending on the isExactInput param, this can be either the input or output
                oppositeAmountBound : 0,
                deadline : block.timestamp + deadline,
                sqrtPriceLimitX96 : 0,
                referralCode : referralCode
            })
        );
    }

    function closePosition(address clearingHouse, address vToken, bytes32 referralCode) external {
        IClearingHouse(clearingHouse).closePosition(
            IClearingHouse.ClosePositionParams({
                baseToken : vToken,
                sqrtPriceLimitX96 : 0,
                oppositeAmountBound : 0,
                deadline : block.timestamp + deadline,
                referralCode : referralCode
            })
        );
    }

    function getAccountValue(address clearingHouse) view external returns (int256) {
        (bool success, bytes memory returnBytes) = clearingHouse.staticcall(
            abi.encodeWithSignature("getAccountValue(address)", address(this))
        );
        require(success, "PL: Failed to get account value");
        return abi.decode(returnBytes, (int256));
    }

    function getDailyMarketTwap160X96(address clearingHouse, address vToken) public view returns(uint160 sqrtMarkTwap) {
        (bool success, bytes memory returnBytes) = clearingHouse.staticcall(
            abi.encodeWithSignature("getExchange()")
        );
        require(success, "PL: Failed to fetch exchange address");
        address exchange = abi.decode(returnBytes, (address));
        (bool successTwap, bytes memory returnBytesTwap) = exchange.staticcall(
            abi.encodeWithSignature("getSqrtMarkTwapX96(address, uint32)", vToken, hour)
        );
        require(successTwap, "PL: Failed to get SqrtMarkTwapX96 ");
        return abi.decode(returnBytesTwap, (uint160));
    }

    function getUSDIndexPrice(address token, uint256 interval) public view returns (uint256) {
        (bool success, bytes memory returnBytes) = token.staticcall(
            abi.encodeWithSignature("getIndexPrice(uint256)")
        );
        require(success, "PL: failed to fetch index price");
        return abi.decode(returnBytes, (uint256)) / 1e12;
    }
}

library Uniswap {

    uint24 constant poolFee = 500;

    function swapAmount(address router, address tokenA, address tokenB, uint256 amountA) external returns (uint256) {
        require(amountA > 0, "UL: Cannot swap zero amount");
        return IV3SwapRouter(router).exactInputSingle(
            IV3SwapRouter.ExactInputSingleParams({
                tokenIn: tokenA,
                tokenOut: tokenB,
                fee: poolFee,
                recipient: address(this),
                amountIn: amountA,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // We want to sell `tokenA` for `tokenB` and receive `amount` of `tokenB`
    // We want to spend no more than `amountInMaximum` of tokenA
    function swapQuotedAmount(address router,
        address tokenA,
        address tokenB,
        uint256 amountAMaximum,
        uint256 amountB) external returns (uint256) {
        require(amountB > 0, "UL: Cannot swap for zero amount");
        require(amountB > 0, "UL: Specify maximum amount to spend");
        return IV3SwapRouter(router).exactOutputSingle(
            IV3SwapRouter.ExactOutputSingleParams({
                tokenIn: tokenA,
                tokenOut: tokenB,
                fee: poolFee,
                recipient: address(this),
                amountOut: amountB,
                amountInMaximum: amountAMaximum,
                sqrtPriceLimitX96: 0
            })
        );
    }
}

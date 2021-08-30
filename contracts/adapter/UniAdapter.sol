// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/ISwapAdapter.sol";
import "../interfaces/ISwapPair.sol";

contract UniAdapter is ISwapAdapter {
    using SafeMath for uint;

    //fromToken == token0
    function sellBase(address to, address pool, bytes memory) external override {
        address baseToken = ISwapPair(pool).token0();
        (uint reserveIn, uint reserveOut,) = ISwapPair(pool).getReserves();
        require(reserveIn > 0 && reserveOut > 0, 'UniAdapter: INSUFFICIENT_LIQUIDITY');

        uint balance0 = IERC20(baseToken).balanceOf(pool);
        uint sellBaseAmount = balance0 - reserveIn;

        uint sellBaseAmountWithFee = sellBaseAmount.mul(997);
        uint numerator = sellBaseAmountWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(sellBaseAmountWithFee);
        uint receiveQuoteAmount = numerator / denominator;
        ISwapPair(pool).swap(0, receiveQuoteAmount, to, new bytes(0));
    }

    //fromToken == token1
    function sellQuote(address to, address pool, bytes memory) external override {
        address quoteToken = ISwapPair(pool).token1();
        (uint reserveOut, uint reserveIn,) = ISwapPair(pool).getReserves();
        require(reserveIn > 0 && reserveOut > 0, 'UniAdapter: INSUFFICIENT_LIQUIDITY');

        uint balance1 = IERC20(quoteToken).balanceOf(pool);
        uint sellQuoteAmount = balance1 - reserveIn;

        uint sellQuoteAmountWithFee = sellQuoteAmount.mul(997);
        uint numerator = sellQuoteAmountWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(sellQuoteAmountWithFee);
        uint receiveBaseAmount = numerator / denominator;
        ISwapPair(pool).swap(receiveBaseAmount, 0, to, new bytes(0));
    }
}
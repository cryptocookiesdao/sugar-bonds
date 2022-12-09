// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "./HelperSetupUniswap.sol";
import "./mocks/Token.sol";
import "./mocks/MockOracle.sol";
import {WETH} from "solmate/tokens/WETH.sol";
import {StrategyBuyAddLiquidity} from "../src/Strategy.sol";

contract AlwaysFail {
    fallback() external {
        revert();
    }
}

contract StrategyTest is UnisetupTest {
    Token public token;
    MockOracle public oracle;

    StrategyBuyAddLiquidity strategy;

    address treasury = makeAddr("treasury");

    function setUp() public {
        deployFactory();

        token = new Token();
        oracle = new MockOracle();
        token.mint(20000 ether);
        weth.deposit{value: 10000 ether}();

        token.approve(address(uniswapV2Router), type(uint256).max);

        uniswapV2Router.addLiquidity(
            address(weth),
            address(token),
            10000 ether,
            20000 ether,
            10000 ether,
            20000 ether,
            address(this),
            block.timestamp + 60
        );

        strategy =
        new StrategyBuyAddLiquidity(address(weth), address(token), address(uniswapV2Router), address(oracle), treasury);
    }

    function testBasicStrategy() public {
        weth.deposit{value: 100 ether}();
        weth.transfer(address(strategy), 100 ether);
        assertEq(weth.balanceOf(address(strategy)), 100 ether);

        // lets imagin that expected price is 0.2 ether
        oracle.setPrice(0.2 ether);
        // but someone manipulate the price to 0.5 ether

        strategy.run();
        // so we should still be having the 100 ether
        assertEq(weth.balanceOf(address(strategy)), 100 ether);

        // lets now set the price to 0.5 ether, that should trigger the strategy because is around the current LP price
        oracle.setPrice(0.5 ether);
        strategy.run(100 ether);
        assertEq(weth.balanceOf(address(strategy)), 0);
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "v2-core/interfaces/IUniswapV2Factory.sol";

import {WETH} from "solmate/tokens/WETH.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {ZuniswapV2Factory} from "zuniswapv2/ZuniswapV2Factory.sol";
import {ZuniswapV2Router} from "zuniswapv2/ZuniswapV2Router.sol";
import {ZuniswapV2Pair} from "zuniswapv2/ZuniswapV2Pair.sol";

abstract contract UnisetupTest is Test {
    address uniswapV2Factory;
    ZuniswapV2Router uniswapV2Router;

    WETH weth;

    function deployFactory() internal {
        require(address(weth) == address(0), "weth not initialized");

        weth = new WETH();

        vm.label(address(weth), "WETH");

        uniswapV2Factory = address(new ZuniswapV2Factory());
        uniswapV2Router = new ZuniswapV2Router(uniswapV2Factory);
        weth.approve(address(uniswapV2Router), type(uint256).max);
    }
    /*
    function createPairs() public {
        IERC20(CKIE).approve(uniswapV2Router, type(uint256).max);
        IERC20(DAI).approve(uniswapV2Router, type(uint256).max);
        IERC20(SUSD).approve(uniswapV2Router, type(uint256).max);

        WETH(payable(weth)).deposit{value: 10369.58540543 ether}();
        IERC20Burneable(CKIE).mint(address(this), 12325.40694347 ether);

        IUniswapV2Router02(uniswapV2Router).addLiquidity(
            weth,
            CKIE,
            10369.58540543 ether,
            12325.40694347 ether,
            10369.58540543 ether,
            12325.40694347 ether,
            address(this),
            block.timestamp + 60
        );
    }

    function setUp() public virtual {
        // deploy WETH, CKIE, DAI, SUSD
        deployFactory();

        createPairs();
    }*/
}

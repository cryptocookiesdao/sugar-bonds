pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Strategy.sol";

interface O {
  function transferOwnership(address newOwner) external;
}

contract MyScript is Script {
    function run() external {
        address token = 0x3C0Bd2118a5E61C41d2aDeEBCb8B7567FDE1cBaF;
        address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;        
        address oracle = 0x48CdAB9efCDD9Fb3132B6cc730A7AD907d52B627;
        address router = 0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff;
        address treasury = 0x40Fd228E9affD14C11a6df17CC7806A0d905ee93;
        vm.startBroadcast();
        StrategyBuyAddLiquidity strategy = new StrategyBuyAddLiquidity(wmatic, token, router, oracle, treasury);
        vm.stopBroadcast();

        console.log("strategy", address(strategy));
    }
}
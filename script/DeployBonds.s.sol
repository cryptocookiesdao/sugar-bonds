pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Bonds.sol";

contract MyScript is Script {
    function run() external {
        address token = 0x3C0Bd2118a5E61C41d2aDeEBCb8B7567FDE1cBaF;
        address wmatic = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
        address oracle = 0x48CdAB9efCDD9Fb3132B6cc730A7AD907d52B627;
        address game = 0x14dB5c0C433a05CAEb78DD7515CbAf67aa772d77;

        vm.startBroadcast();
        CryptoCookiesBondsV2 bonds = new CryptoCookiesBondsV2(token, wmatic, oracle, game);
        // game.call(abi.encodeWithSignature("setBondsMinter(address)", address(bonds)));
        // CryptoCookiesBondsV2 bonds = CryptoCookiesBondsV2(0xEa3804b69a86CD93A35e00042EDFA890aa8F61bA);
        // bonds.startBondSell(5, 0, 25_0000, 1_0000, 10 ether, 0xa4016ec301cfB85a2a87CC3FA320BBd24a05c477 /*makeAddr("strategy")*/, "bonos test");
        vm.stopBroadcast();

        // console.log("bonds", address(bonds));
    }
}

pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/Bonds.sol";

contract MyScript is Script {
    function run() external {
        address strategy = 0xb2f1F157c7322B4656e5D12d9db20A0C92a4dBdb;
        CryptoCookiesBondsV2 bonds = CryptoCookiesBondsV2(0xEa3804b69a86CD93A35e00042EDFA890aa8F61bA);
        address game = 0x14dB5c0C433a05CAEb78DD7515CbAf67aa772d77;

        vm.startBroadcast();
        game.call(abi.encodeWithSignature("setBondsMinter(address)", address(bonds)));
        bonds.startBondSell(5, 0, 25_0000, 1_0000, 50 ether, strategy, "First bond sell :D");   
        game.call(abi.encodeWithSignature("setBondsMinter(address)", address(0)));
        
        vm.stopBroadcast();

        // console.log("bonds", address(bonds));
    }
}

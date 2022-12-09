// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Bonds.sol";
import "./mocks/Token.sol";
import "./mocks/MockOracle.sol";
import "./mocks/MockGame.sol";
import {WETH} from "solmate/tokens/WETH.sol";

contract AlwaysFail {
    fallback() external {
        revert();
    }
}

contract BondsTest is Test {
    CryptoCookiesBondsV2 public bonds;
    Token public token;
    WETH public weth;
    MockOracle public oracle;

    address[] private _targetContracts;
    uint256 totalSupply;

    function targetContracts() public view returns (address[] memory targetContracts_) {
        require(_targetContracts.length != uint256(0), "NO_TARGET_CONTRACTS");
        return _targetContracts;
    }

    function _addTargetContract(address newTargetContract_) internal {
        _targetContracts.push(newTargetContract_);
    }

    function setUp() public {
        token = new Token();
        oracle = new MockOracle();
        weth = new WETH();
        address game = address(new MockGame(address(token)));

        bonds = new CryptoCookiesBondsV2(address(token), address(weth), address(oracle), game);

        uint256 CKIE_PRICE = 1 ether;
        oracle.setPrice(CKIE_PRICE);
        bonds.startBondSell(5, 0, 25_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");
        bonds.startBondSell(6, 0, 30_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");

        _addTargetContract(address(bonds));
        _addTargetContract(address(weth));

        totalSupply = token.totalSupply();
    }

    function invariant_cantOverMint() public {
        assertTrue(token.totalSupply() == totalSupply);
    }
}

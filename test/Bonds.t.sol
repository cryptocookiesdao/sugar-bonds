// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Bonds.sol";
import "../src/mocks/Token.sol";
import "../src/mocks/MockOracle.sol";
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

    function setUp() public {
        token = new Token();
        oracle = new MockOracle();
        weth = new WETH();
        bonds = new CryptoCookiesBondsV2(address(token), address(weth), address(oracle));
    }

    function testCreateBondPrices() public {
        uint256 CKIE_PRICE = 1 ether;
        oracle.setPrice(CKIE_PRICE);
        bonds.startBondSell(5, 0, 25_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");
        assertEq(token.balanceOf(address(bonds)), 10.1 ether);
        bonds.startBondSell(6, 0, 30_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");
        assertEq(token.balanceOf(address(bonds)), 20.2 ether);

        assertEq(bonds.currentDiscount(0), 0);
        assertEq(bonds.currentDiscount(1), 0);

        for (uint256 _hours = 1; _hours <= 24 * 25; ++_hours) {
            vm.warp(3600 * _hours);
            uint256 expected = uint256(1_0000 * 3600 * _hours) / uint256(1 days);
            assertApproxEqAbs(bonds.currentDiscount(0), expected, 2);
            assertApproxEqAbs(bonds.currentDiscount(1), expected, 2);

            assertApproxEqAbs(
                bonds.priceOfCookieWithDiscount(0), CKIE_PRICE * (100_0000 - expected) / 100_0000, 0.00001 ether
            );
            assertApproxEqAbs(
                bonds.priceOfCookieWithDiscount(1), CKIE_PRICE * (100_0000 - expected) / 100_0000, 0.00001 ether
            );
        }
        skip(30 days);

        assertApproxEqAbs(
            bonds.priceOfCookieWithDiscount(0), CKIE_PRICE - CKIE_PRICE * 25_0000 / 100_0000, 0.00001 ether
        );
        assertApproxEqAbs(
            bonds.priceOfCookieWithDiscount(1), CKIE_PRICE - CKIE_PRICE * 30_0000 / 100_0000, 0.00001 ether
        );
    }

    function testCreateBond() public {
        oracle.setPrice(1 ether);

        vm.expectRevert();
        bonds.startBondSell(5, 6_0000, 5_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");

        bonds.startBondSell(5, 0, 25_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");
        assertEq(token.balanceOf(address(bonds)), 10.1 ether);
        bonds.startBondSell(6, 0, 30_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");
        assertEq(token.balanceOf(address(bonds)), 20.2 ether);

        vm.deal(makeAddr("bob"), 10 ether);
        vm.startPrank(makeAddr("bob"));

        vm.expectRevert(bytes("UNAUTHORIZED"));
        bonds.startBondSell(5, 0, 25_0000, 1_0000, 10 ether, makeAddr("strategy"), "bonos test");

        bonds.buyBond{value: 1 ether}(0);
        vm.expectRevert();
        bonds.buyBond{value: 1 ether}(2);

        vm.expectRevert(bytes("UNAUTHORIZED"));
        bonds.endBondSell(0);

        vm.stopPrank();

        assertEq(bonds.activeBonds(0), 0);
        assertEq(bonds.activeBonds(1), 1);

        vm.warp(25 days);
        assertApproxEqAbs(bonds.currentDiscount(0), 25_0000, 2);
        assertApproxEqAbs(bonds.currentDiscount(1), 25_0000, 2);
        skip(2 days);
        assertApproxEqAbs(bonds.currentDiscount(0), 25_0000, 2);
        assertApproxEqAbs(bonds.currentDiscount(1), 27_0000, 2);

        skip(3 days);
        assertApproxEqAbs(bonds.currentDiscount(0), 25_0000, 2);
        assertApproxEqAbs(bonds.currentDiscount(1), 30_0000, 2);

        skip(3 days);
        assertApproxEqAbs(bonds.currentDiscount(0), 25_0000, 2);
        assertApproxEqAbs(bonds.currentDiscount(1), 30_0000, 2);

        bonds.endBondSell(0);
        assertEq(bonds.activeBonds(0), 1);
        bonds.endBondSell(1);

        vm.expectRevert();
        bonds.currentDiscount(0);
        vm.expectRevert();
        bonds.currentDiscount(1);
    }

    function testCreateEndBond(uint256 elements, uint256 seed) public {
        elements = elements % 20;
        vm.assume(elements > 0);
        uint256[] memory exist = new uint256[](elements);

        for (uint256 i; i < elements; ++i) {
            exist[i] = i;
        }

        for (uint256 i = 0; i < exist.length; i++) {
            uint256 n = i + seed % (exist.length - i);
            seed = uint256(keccak256(abi.encodePacked(seed)));
            uint256 temp = exist[n];
            exist[n] = exist[i];
            exist[i] = temp;
        }

        oracle.setPrice(1 ether);
        for (uint256 i; i < elements; ++i) {
            bonds.startBondSell(5, 0, 25_0000, 1_0000, 1 ether, makeAddr("strategy"), "bonos test");
        }

        for (uint256 i; i < elements; ++i) {
            assertEq(bonds.activeBonds(i), i);
            assertEq(bonds.currentDiscount(uint128(i)), 0);
            assertEq(bonds.priceOfCookieWithDiscount(uint128(i)), 1 ether);
        }

        for (uint256 i; i < elements; ++i) {
            uint256 prevLen = bonds.activeBondsLength();
            assertEq(bonds.currentDiscount(uint128(exist[i])), 0);
            bonds.endBondSell(uint128(exist[i]));
            assertEq(bonds.activeBondsLength(), prevLen - 1);

            for (uint256 j; j < prevLen - 1; ++j) {
                assertFalse(uint128(exist[i]) == bonds.activeBonds(j));
            }
        }
    }

    function testNotesBuy() public {
        oracle.setPrice(1 ether);

        address strategyA = address(new AlwaysFail());

        bonds.startBondSell(5, 0, 25_0000, 1_0000, 1 ether, strategyA, "bonos test A");
        bonds.startBondSell(5, 0, 25_0000, 1_0000, 1 ether, strategyA, "bonos test A");

        address alice = makeAddr("alice");
        vm.deal(alice, 10 ether);

        assertEq(weth.balanceOf(strategyA), 0 ether);

        vm.startPrank(alice);
        bonds.buyBond{value: 0.2 ether}(0);
        bonds.buyBond{value: 0.2 ether}(0);
        bonds.buyBond{value: 0.2 ether}(0);
        bonds.buyBond{value: 0.2 ether}(0);
        bonds.buyBond{value: 2 ether}(0);
        vm.expectRevert();
        bonds.buyBond{value: 2 ether}(0);

        assertEq(alice.balance, 9 ether);
        assertEq(weth.balanceOf(strategyA), 1 ether);

        assertEq(bonds.totalToRedeem(alice), 0);

        for (uint256 i = 1; i <= 5; ++i) {
            skip(1 days);
            assertEq(bonds.totalToRedeem(alice), 0.2 ether * i);
        }

        bonds.buyBond{value: 1 ether}(1);

        assertEq(bonds.totalToRedeem(alice), 1 ether);

        for (uint256 i = 1; i <= 5; ++i) {
            skip(1 days);
            assertEq(bonds.totalToRedeem(alice), 1 ether + 0.2 ether * i);
        }

        assertEq(bonds.totalToRedeem(alice), 2 ether);
        bonds.redeem(1);
        assertEq(bonds.totalToRedeem(alice), 1.8 ether);

        assertEq(token.balanceOf(alice), 0.2 ether);

        vm.expectRevert();
        bonds.redeem(1);

        bonds.redeemAll();
        assertEq(bonds.totalToRedeem(alice), 0);
        assertEq(token.balanceOf(alice), 2 ether);
    }

    function testNotes() public {
        oracle.setPrice(1 ether);

        address strategyA = makeAddr("strategyA");
        address strategyB = makeAddr("strategyB");
        address strategyC = makeAddr("strategyC");

        bonds.startBondSell(5, 0, 25_0000, 1_0000, 10 ether, strategyA, "bonos test A");
        bonds.startBondSell(6, 0, 30_0000, 1_0000, 10 ether, strategyB, "bonos test B");
        bonds.startBondSell(6, 0, 30_0000, 5_0000, 1 ether, strategyC, "bonos test C");

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);

        skip(1 days);

        vm.startPrank(alice);
        bonds.buyBond{value: 1 ether}(0); // buy price = 1 ether / 0.99 ether
        bonds.buyBond{value: 1 ether}(1); // buy price = 1 ether / 0.99 ether
        bonds.buyBond{value: 0.5 ether}(2); // buy price = 0.5 ether / 0.95 ether

        uint256 expected = 1 ether * 1 ether / uint256(0.99 ether);
        CryptoCookiesBondsV2.Note memory n = bonds.getNote(alice, 0);
        assertEq(n.totalCookies, expected);
        n = bonds.getNote(alice, 1 /* index (can change)*/ );
        assertEq(n.totalCookies, expected);

        expected = 0.5 ether * 1 ether / uint256(0.95 ether);
        n = bonds.getNote(alice, 2 /* index (can change)*/ );
        assertEq(n.totalCookies, expected);

        skip(2 days);
        // uid note 0

        CryptoCookiesBondsV2.Note[] memory notes = bonds.getNotes(alice);
        expected = 0.5 ether * 1 ether / uint256(0.95 ether);
        assertEq(notes[2].totalCookies, expected);
        expected = 1 ether * 1 ether / uint256(0.99 ether);
        assertEq(notes[1].totalCookies, expected);
        assertEq(notes[0].totalCookies, expected);

        assertEq(notes[0].paid, 0);
        assertEq(notes[1].paid, 0);
        assertEq(notes[2].paid, 0);

        bonds.redeem(0);
        notes = bonds.getNotes(alice);
        assertEq(notes[0].totalCookies, expected);
        assertEq(notes[0].paid, expected * 2 / 5);
        assertEq(notes[1].paid, 0);

        (uint128[] memory notesIds, uint256[] memory pendingAmount) = bonds.toRedeem(alice);
        assertEq(pendingAmount[0], 0);
        assertApproxEqAbs(pendingAmount[1], expected * 2 / 6, 2);

        skip(1 days);
    }
}

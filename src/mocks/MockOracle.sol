// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract MockOracle {
    uint256 private price;

    function setPrice(uint256 _price) external {
        price = _price;
    }

    function update() external {}

    function consult(address, uint256) external view returns (uint256) {
        return price;
    }
}

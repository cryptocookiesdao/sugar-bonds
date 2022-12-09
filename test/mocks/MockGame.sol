// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Token.sol";

contract MockGame {
    Token token;

    constructor(address _token) {
        token = Token(_token);
    }

    function sugarBondMint(uint256 amount) external {
        token.mint(msg.sender, amount);
    }
}

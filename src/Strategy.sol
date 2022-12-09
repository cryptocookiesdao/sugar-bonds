// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IOracleSimple} from "./interfaces/IOracleSimple.sol";

import {IUniswapV2Router02} from "v2-periphery/interfaces/IUniswapV2Router02.sol";

interface IBondManagerStrategy {
    function run() external;
}

contract StrategyBuyAddLiquidity is Owned(msg.sender), IBondManagerStrategy {
    IERC20 immutable WMATIC;
    IERC20 immutable CKIE;
    IUniswapV2Router02 immutable ROUTER;
    IOracleSimple immutable ORACLE;
    address public immutable TREASURY;

    uint16 allowedSlippeage = 4_00; // 4%

    constructor(address _wmatic, address _ckie, address _router, address _oracleSimple, address _treasury) {
        WMATIC = IERC20(_wmatic);
        CKIE = IERC20(_ckie);
        ROUTER = IUniswapV2Router02(_router);
        ORACLE = IOracleSimple(_oracleSimple);
        TREASURY = _treasury;

        IERC20(_wmatic).approve(address(_router), type(uint256).max);
        IERC20(_ckie).approve(address(_router), type(uint256).max);
    }

    /// @notice Withdraw a token or ether stuck in the contract
    /// @param token Address of the ERC20 to withdraw, use address 0 for MATIC
    /// @param amount amount of token to withdraw
    function withdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            ///@dev no need for safeTransfer
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    function changeSlippeage(uint16 _allowedSlippeage) external onlyOwner {
        allowedSlippeage = _allowedSlippeage;
    }

    function run() external {
        uint256 amount = WMATIC.balanceOf(address(this));
        if (amount < 0.1 ether) {
            return;
        }
        run(amount);
    }

    function run(uint256 amount) public {
        address[] memory path = new address[](2);

        // check oracle price TWAP
        uint256 twapPrice = ORACLE.consult(address(WMATIC), 1 ether);

        // check oracle weak price
        path[0] = address(CKIE);
        path[1] = address(WMATIC);
        uint256[] memory simplePrice = ROUTER.getAmountsOut(1 ether, path);

        // if slippeage difference is greater than allowedSlippeage return and do nothing
        unchecked {
            uint256 delta;
            if (simplePrice[1] > twapPrice) {
                delta = simplePrice[1] * 100_00 / twapPrice - 100_00;
                /// @dev if delta is greater than allowedSlippeage someone if messing with the LP (MEV attack)
                if (delta > allowedSlippeage) {
                    return;
                }
            }
            /*
            else {
                /// @dev maybe this case is not that important
                delta = twapPrice * 100_00 / simplePrice[1] - 100_00;
            }
            */
        }

        uint256 half = amount / 2;

        path[0] = address(WMATIC);
        path[1] = address(CKIE);

        ROUTER.swapExactTokensForTokens(half, 0, path, address(this), block.timestamp);

        ROUTER.addLiquidity(
            address(WMATIC), address(CKIE), half, CKIE.balanceOf(address(this)), 0, 0, TREASURY, block.timestamp
        );
    }
}

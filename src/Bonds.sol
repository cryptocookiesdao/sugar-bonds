// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {Owned} from "solmate/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IOracleSimple} from "./interfaces/IOracleSimple.sol";

import "forge-std/Test.sol";

interface IERC20Minteable is IERC20 {
    function mint(uint256 amount) external;
    function burn(uint256 amount) external;
}

interface IWETH {
    function deposit() external payable;
}

interface IBondManagerStrategy {
    function run() external;
}

contract CryptoCookiesBondsV2 is Owned(msg.sender) {
    error errWrongDiscount();

    event BondTermsStart(uint128 indexed uid, Bond bond, string details);
    event BondTermsEnd(uint128 indexed uid, uint256 cookieRemains);

    event NoteAdded(address indexed owner, uint256 indexed noteId, uint256 amountMATIC, uint256 cookiesForUser);
    event NoteRedeem(address indexed owner, uint256 indexed noteId, uint256 redeemAmount);

    struct Bond {
        uint128 uid;
        uint40 bondStart;
        uint16 vestingDays;
        uint24 startDiscount;
        uint24 endDiscount;
        uint16 dailyDiscount;
        uint8 disabled;
        uint128 bondedCookies;
        uint128 cookiesToBond;
        address bondManagerStrategy;
    }

    struct Note {
        uint256 uid;
        uint128 uidBond;
        uint40 timestampStart;
        uint40 timestampLastRedeem;
        uint40 timestampEnd;
        uint128 paid;
        uint128 totalCookies;
        address owner;
    }

    /// @dev base percentage 1e6 = 100%
    uint256 constant BASE_PERC = 100_0000;

    uint256 constant BASE_ETH = 1 ether;

    uint128 private _totalBonds;
    uint256 private _noteIdCounter;

    ///@dev CKIE
    IERC20Minteable public immutable COOKIETOKEN;
    ///@dev WMATIC
    address public immutable WMATIC;
    ///@dev TWAP oracle for CKIE price against WMATIC
    IOracleSimple public immutable ORACLE;

    mapping(uint128 => Bond) public bonds;
    mapping(uint128 => Note) public notes;
    mapping(address => uint128[]) public toNotes;

    uint128[] public activeBonds;

    constructor(address _cookieToken, address _wmatic, address _oracleSimple) {
        COOKIETOKEN = IERC20Minteable(_cookieToken);
        WMATIC = _wmatic;
        ORACLE = IOracleSimple(_oracleSimple);
    }

    /// @notice Withdraw a token or ether stuck in the contract
    /// @param token Address of the ERC20 to withdraw, use address 0 for MATIC
    /// @param amount amount of token to withdraw
    function withdraw(address token, uint256 amount) external onlyOwner {
        ///@dev cant withdraw CKIE
        if (token == address(COOKIETOKEN)) {
            revert();
        }

        if (token == address(0)) {
            SafeTransferLib.safeTransferETH(msg.sender, amount);
        } else {
            ///@dev no need for safeTransfer
            IERC20(token).transfer(msg.sender, amount);
        }
    }

    /// @notice Explain to an end user what this does
    /// @param _vestingDays number of day for vesting the bond
    /// @param _startDiscount BPS discount start (recommend 0)
    /// @param _endDiscount BPS discount max
    /// @param _dailyDiscount daily BPS discount
    /// @param _cookiesToBond amount of CKIE to sell
    /// @param _bondManagerStrategy address of the contract that will manage the WMATIC
    /// @param details string details of the bond (for graphql)
    function startBondSell(
        uint16 _vestingDays,
        uint24 _startDiscount,
        uint24 _endDiscount,
        uint16 _dailyDiscount,
        uint128 _cookiesToBond,
        address _bondManagerStrategy,
        string memory details
    ) external onlyOwner {
        require(_cookiesToBond > 0, "No cookies to bond");
        if (_startDiscount > _endDiscount) {
            revert errWrongDiscount();
        }

        uint128 bondUid;
        unchecked {
            // Adds 101% from _cookiesToBond, 1% extramint go for the devs
            COOKIETOKEN.mint((_cookiesToBond * 101) / 100);
            bondUid = _totalBonds++;
        }
        activeBonds.push(bondUid);

        emit BondTermsStart(
            bondUid,
            bonds[bondUid] = Bond({
                uid: bondUid,
                bondStart: uint40(block.timestamp),
                vestingDays: _vestingDays,
                startDiscount: _startDiscount,
                endDiscount: _endDiscount,
                dailyDiscount: _dailyDiscount,
                disabled: 0,
                bondedCookies: 0,
                cookiesToBond: _cookiesToBond,
                bondManagerStrategy: _bondManagerStrategy
            }),
            details
            );
    }

    function endBondSell(uint128 uid) external onlyOwner {
        _endBondSell(uid);
    }

    function _endBondSell(uint128 uid) private {
        Bond memory _bond = bonds[uid];
        require(_bond.disabled == 0, "Bond is terminated");
        uint256 cookieRemains = _bond.cookiesToBond - _bond.bondedCookies;
        if (cookieRemains > 0) {
            COOKIETOKEN.burn(cookieRemains);
        }
        bonds[uid].disabled = 1;

        uint128[] storage _activeBonds = activeBonds;
        uint256 len = _activeBonds.length;

        unchecked {
            uint256 pos;
            while (true) {
                if (_activeBonds[pos] == uid) {
                    break;
                }
                ++pos;
            }

            if (len - 1 != pos) {
                _activeBonds[pos] = _activeBonds[len - 1];
            }
        }

        _activeBonds.pop();

        emit BondTermsEnd(uid, cookieRemains);
    }

    function buyBond(uint128 uid) external payable {
        Bond storage _bond = bonds[uid];
        require(_bond.cookiesToBond > 0, "The bond was ended");
        require(_bond.disabled < 1, "Bond is terminated");

        // update oracle if needed
        ORACLE.update();

        uint128 value = uint128(msg.value);
        uint16 vestingDays = _bond.vestingDays;

        uint128 discountPrice = priceOfCookieWithDiscount(uid);
        uint128 cookiesForUser = (value * uint128(BASE_ETH)) / discountPrice;

        uint128 cookieRemains = _bond.cookiesToBond - _bond.bondedCookies;
        if (cookieRemains <= cookiesForUser) {
            cookiesForUser = cookieRemains;
            value = (cookieRemains * discountPrice) / uint128(BASE_ETH);
        }
        bonds[uid].bondedCookies += uint128(cookiesForUser);

        // @dev 100% / 100 = 1%, 1% for devs
        uint256 forDev = cookiesForUser / 100;
        COOKIETOKEN.transfer(owner, forDev);

        uint128 noteUid;
        unchecked {
            noteUid = uint128(_noteIdCounter++);

            notes[noteUid] = Note({
                uid: noteUid,
                uidBond: _bond.uid,
                timestampStart: uint40(block.timestamp),
                timestampLastRedeem: uint40(block.timestamp),
                timestampEnd: uint40(block.timestamp + vestingDays * 1 days),
                paid: 0,
                totalCookies: cookiesForUser,
                owner: msg.sender
            });
        }

        toNotes[msg.sender].push(noteUid);

        /// @dev wrap MATIC
        IWETH(WMATIC).deposit{value: value}();
        IERC20(WMATIC).transfer(_bond.bondManagerStrategy, value);

        // ignore return if something goes wrong we could do it later
        _bond.bondManagerStrategy.call(abi.encodeWithSignature("run()"));

        emit NoteAdded(msg.sender, noteUid, value, cookiesForUser);

        if (_bond.cookiesToBond == _bond.bondedCookies) {
            _endBondSell(uid);
        }

        if (value < msg.value) {
            unchecked {
                SafeTransferLib.safeTransferETH(msg.sender, msg.value - value);
            }
        }
    }

    function redeemAll() external {
        uint128[] memory _notes = toNotes[msg.sender];
        uint256 len = _notes.length;
        unchecked {
            while (len > 0) {
                redeem(_notes[--len]);
            }
        }
    }

    function redeem(uint128 noteId) public returns (bool resize) {
        Note storage note = notes[noteId];
        require(note.owner == msg.sender, "!noteOwner");

        uint256 redeemAmount = _toRedeem(noteId);

        if (redeemAmount == 0) {
            revert();
        }

        note.timestampLastRedeem = uint40(block.timestamp);
        unchecked {
            note.paid += uint128(redeemAmount);
        }

        if (note.paid == note.totalCookies) {
            _deleteNote(msg.sender, noteId);
            resize = true;
        }

        COOKIETOKEN.transfer(msg.sender, redeemAmount);
        emit NoteRedeem(msg.sender, noteId, redeemAmount);
    }

    function getNote(address account, uint256 index) external view returns (Note memory) {
        return notes[toNotes[account][index]];
    }

    function getNotes(address account) external view returns (Note[] memory) {
        uint256 len = toNotes[account].length;
        Note[] memory ret = new Note[](len);
        for (uint256 i; i < len; ++i) {
            ret[i] = notes[toNotes[account][i]];
        }
        return ret;
    }

    function notesLength(address account) public view returns (uint256) {
        return toNotes[account].length;
    }

    function activeBondsLength() public view returns (uint256) {
        return activeBonds.length;
    }

    function currentDiscount(uint128 uid) public view returns (uint24 discount) {
        Bond memory _bond = bonds[uid];
        require(_bond.disabled == 0, "Bond is terminated");

        unchecked {
            discount = uint24(
                _bond.startDiscount + ((uint40(block.timestamp) - _bond.bondStart) * _bond.dailyDiscount) / 1 days
            );
        }

        if (discount > _bond.endDiscount) {
            discount = _bond.endDiscount;
        }

        if (discount > BASE_PERC) {
            discount = uint24(BASE_PERC);
        }
    }

    function priceOfCookieWithDiscount(uint128 uid) public view returns (uint128 discountPrice) {
        discountPrice = uint128(ORACLE.consult(address(COOKIETOKEN), uint256(BASE_ETH)));
        unchecked {
            discountPrice = discountPrice * (uint128(BASE_PERC) - currentDiscount(uid)) / uint128(BASE_PERC);
        }
    }

    function _toRedeem(uint128 _noteId) internal view returns (uint256 ret) {
        Note memory note = notes[_noteId];
        uint256 _timestampEnd = note.timestampEnd;
        uint256 _totalCookies = note.totalCookies;

        if (block.timestamp > _timestampEnd) {
            uint256 _paid = note.paid;
            assembly {
                ret := sub(_totalCookies, _paid)
            }
        } else {
            uint256 _timestampLastRedeem = note.timestampLastRedeem;
            uint256 _timestampStart = note.timestampStart;

            assembly {
                if lt(timestamp(), _timestampLastRedeem) { revert(0, 0) }
                let deltaY := sub(timestamp(), _timestampLastRedeem)
                let redeemPerc := div(mul(deltaY, BASE_ETH), sub(_timestampEnd, _timestampStart))
                ret := div(mul(_totalCookies, redeemPerc), BASE_ETH)
            }
        }
    }

    function toRedeem(address _account)
        external
        view
        returns (uint128[] memory notesIds, uint256[] memory pendingAmount)
    {
        notesIds = toNotes[_account];
        uint256 len = notesIds.length;
        pendingAmount = new uint256[](len);
        unchecked {
            for (uint256 i; i < len; ++i) {
                pendingAmount[i] = _toRedeem(uint128(notesIds[i]));
            }
        }
    }

    function totalToRedeem(address account) external view returns (uint256 pendingAmount) {
        uint128[] memory notesIds = toNotes[account];
        uint256 len = notesIds.length;
        unchecked {
            for (uint256 i; i < len; ++i) {
                pendingAmount = pendingAmount + _toRedeem(uint128(notesIds[i]));
            }
        }
    }

    function _deleteNote(address account, uint256 noteUid) internal {
        uint128[] storage userNotes = toNotes[account];
        uint256 len = userNotes.length;

        unchecked {
            uint256 pos;
            while (true) {
                if (userNotes[pos] == noteUid) {
                    break;
                }
                ++pos;
            }

            if (len - 1 != pos) {
                userNotes[pos] = userNotes[len - 1];
            }
        }

        userNotes.pop();
    }
}

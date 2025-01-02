// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {ERC721CollateralLoan} from "./ERC721CollateralLoan.sol";

/// @title Tintero Protocol
///
/// @notice An [ERC4626](https://docs.openzeppelin.com/contracts/5.x/erc4626) vault that receives
/// an ERC20 token in exchange for shares and allocates these assets towards funding Loan contracts.
contract Tintero is ERC4626, AccessManaged, ERC721Holder {
    using Clones for address;
    using EnumerableSet for EnumerableSet.AddressSet;

    address public immutable ERC721_COLLATERAL_LOAN_IMPLEMENTATION =
        address(new ERC721CollateralLoan());

    // Invariant: _totalAssetsLent == sum(_lentTo)
    uint256 private _totalAssetsLent;
    mapping(address loan => uint256 assets) private _lentTo;
    EnumerableSet.AddressSet private _loans;

    constructor(
        IERC20Metadata asset_,
        address authority_
    )
        ERC20(_t(asset_.name()), _t(asset_.symbol()))
        ERC4626(asset_)
        AccessManaged(authority_)
    {}

    /**********************/
    /*** View Functions ***/
    /**********************/

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + _totalAssetsLent;
    }

    /// @dev The total amount of assets lent to Loan contracts.
    function totalAssetsLent() external view returns (uint256) {
        return _totalAssetsLent;
    }

    /// @dev The total amount of assets lent to a Loan contract.
    function lentTo(address _loan) external view returns (uint256) {
        return _lentTo[_loan];
    }

    /// @dev The maximum amount of assets that can be withdrawn.
    /// This is the maximum between the owner's max withdrawable assets and the vault's asset balance.
    function maxWithdraw(address owner) public view override returns (uint256) {
        IERC20Metadata asset_ = IERC20Metadata(asset());

        return
            Math.max(
                super.maxWithdraw(owner), // Max owner withdrawable assets
                asset_.balanceOf(owner) // Total available vault's asset balance
            );
    }

    /// @dev The maximum amount of shares that can be redeemed.
    /// This is the minimum between the owner's max redeemable shares and the vault's asset balance.
    function maxRedeem(address owner) public view override returns (uint256) {
        IERC20Metadata asset_ = IERC20Metadata(asset());
        return
            Math.min(
                super.maxRedeem(owner), // Max owner redeemable shares
                convertToShares(asset_.balanceOf(owner)) // Max amount of shares redeemable for vault's asset balance
            );
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    function predictLoanAddress(
        bytes32 salt,
        address caller_
    ) external view returns (address) {
        return _predictLoanAddress(_salt(salt, caller_));
    }

    function requestLoan(
        address collateralCollection_,
        address beneficiary_,
        uint16 defaultThreshold_,
        PaymentLib.Payment[] calldata payments_,
        uint256[] calldata collateralTokenIds_,
        bytes32 salt
    ) external {
        salt = _salt(salt, msg.sender);
        address predicted = _predictLoanAddress(salt);
        require(_loans.add(predicted));

        if (predicted.code.length == 0) {
            ERC721_COLLATERAL_LOAN_IMPLEMENTATION.cloneDeterministic(salt);
            ERC721CollateralLoan(predicted).initialize(
                authority(),
                address(this),
                collateralCollection_,
                beneficiary_,
                defaultThreshold_,
                payments_,
                collateralTokenIds_
            );
        }
    }

    /*************************/
    /*** Manager Functions ***/
    /*************************/

    function relay(
        ERC721CollateralLoan loan,
        bytes calldata data
    ) external restricted {
        address loan_ = address(loan);
        require(_loans.contains(loan_));

        uint256 assetsBalance = totalAssets();
        Address.functionCall(loan_, data);

        bytes4 selector = bytes4(data[0:4]);

        if (selector == loan.fundN.selector) {
            uint256 newAssetsBalance = totalAssets();
            uint256 totalPrincipalFunded = newAssetsBalance - assetsBalance;
            _lentTo[loan_] += totalPrincipalFunded;
            _totalAssetsLent += totalPrincipalFunded;
        } else if (selector == loan.reposses.selector) {
            uint256 newAssetsBalance = totalAssets();
            uint256 totalPrincipalLost = assetsBalance - newAssetsBalance;
            _lentTo[loan_] -= totalPrincipalLost;
            _totalAssetsLent -= totalPrincipalLost;
        } else assert(assetsBalance == totalAssets());
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /// @dev Virtual offset to defend against inflation attacks.
    /// See https://docs.openzeppelin.com/contracts/5.x/erc4626#defending_with_a_virtual_offset
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    function _predictLoanAddress(bytes32 salt) internal view returns (address) {
        return
            ERC721_COLLATERAL_LOAN_IMPLEMENTATION.predictDeterministicAddress(
                salt,
                address(this)
            );
    }

    /*************************/
    /*** Private Functions ***/
    /*************************/

    function _t(string memory _str) internal pure returns (string memory) {
        return string(abi.encodePacked("t", _str));
    }

    /// @dev Implementation of keccak256(abi.encode(a, b)) that doesn't allocate or expand memory.
    function _salt(
        bytes32 salt,
        address caller_
    ) internal pure returns (bytes32) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            value := keccak256(0x00, 0x40)
        }
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) public override returns (bytes4) {
        require(_loans.contains(operator));
        return super.onERC721Received(operator, from, tokenId, data);
    }
}

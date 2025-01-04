// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {TinteroLoan} from "./TinteroLoan.sol";
import {TinteroLoanFactory} from "./TinteroLoan.factory.sol";

/// @title Tintero Vault
///
/// @notice An [ERC4626](https://docs.openzeppelin.com/contracts/5.x/erc4626) vault that receives
/// an ERC20 token in exchange for shares and allocates these assets towards funding Loan contracts.
contract Tintero is ERC4626, ERC721Holder, TinteroLoanFactory {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Reverts if a Loan contract is already created by this vault.
    error DuplicatedLoan();

    /// @dev Reverts if the caller is not a Loan contract created by this vault.
    error OnlyAuthorizedLoan();

    // Invariant: _totalAssetsLent == sum(_lentTo)
    uint256 private _totalAssetsLent;
    mapping(address loan => uint256 assets) private _lentTo;
    EnumerableSet.AddressSet private _loans;

    /// @dev Constructor for Tintero.
    ///
    /// @param asset_ The ERC20 token to be lent.
    /// @param authority_ The access manager for the vault.
    constructor(
        IERC20Metadata asset_,
        address authority_
    )
        ERC20(_prefix("t", asset_.name()), _prefix("Tinted", asset_.symbol()))
        ERC4626(asset_)
        AccessManaged(authority_)
    {}

    /**********************/
    /*** View Functions ***/
    /**********************/

    /// @dev Receives ERC721 tokens from Loan contracts and updates the total lent assets.
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes memory data
    ) public override returns (bytes4) {
        if (!isLoan(operator)) revert OnlyAuthorizedLoan();
        uint256 principal = abi.decode(data, (uint256));
        _lentTo[operator] -= principal;
        return super.onERC721Received(operator, from, tokenId, data);
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view override returns (uint256) {
        return super.totalAssets() + _totalAssetsLent;
    }

    /// @dev The total amount of assets lent to Loan contracts.
    function totalAssetsLent() public view returns (uint256) {
        return _totalAssetsLent;
    }

    /// @dev The total amount of assets lent to a Loan contract.
    function lentTo(address _loan) public view returns (uint256) {
        return _lentTo[_loan];
    }

    function isLoan(address loan) public view returns (bool) {
        return _loans.contains(loan);
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

    /// @dev Creates a new instance of a Loan contract with the provided parameters.
    function requestLoan(
        address collateralCollection_,
        address beneficiary_,
        uint16 defaultThreshold_,
        PaymentLib.Payment[] calldata payments_,
        uint256[] calldata collateralTokenIds_,
        bytes32 salt
    ) external {
        address predicted = _deployLoan(
            salt,
            collateralCollection_,
            beneficiary_,
            defaultThreshold_,
            payments_,
            collateralTokenIds_
        );
        if (!_loans.add(predicted)) revert DuplicatedLoan();
    }

    /*************************/
    /*** Manager Functions ***/
    /*************************/

    /// @dev Adds a list of payments to a Loan contract. Calls Loan#pushPayments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    function pushPayments(
        TinteroLoan loan,
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payment_
    ) external restricted {
        if (!isLoan(address(loan))) revert OnlyAuthorizedLoan();

        loan.pushPayments(collateralTokenIds, payment_);
    }

    /// @dev Funds `n` payments from a Loan contract. Calls Loan#fundN.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    function fundN(TinteroLoan loan, uint256 n) external restricted {
        address loan_ = address(loan);
        if (!isLoan(loan_)) revert OnlyAuthorizedLoan();

        IERC20Metadata asset_ = IERC20Metadata(asset());
        uint256 assetsBalance = asset_.balanceOf(address(this));
        loan.fundN(n);
        uint256 newAssetsBalance = asset_.balanceOf(address(this));
        uint256 totalPrincipalFunded = newAssetsBalance - assetsBalance;
        _lentTo[loan_] += totalPrincipalFunded;
        _totalAssetsLent += totalPrincipalFunded;
    }

    /// @dev Repossess a range of payments from a Loan contract. Calls Loan#repossess.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    function repossess(
        TinteroLoan loan,
        uint256 start,
        uint256 end
    ) external restricted {
        address loan_ = address(loan);
        if (!isLoan(loan_)) revert OnlyAuthorizedLoan();

        uint256 principalLost = _lentTo[loan_];
        loan.repossess(start, end);
        _totalAssetsLent -= principalLost;
        assert(_lentTo[loan_] == 0);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /// @dev Virtual offset to defend against inflation attacks.
    /// See https://docs.openzeppelin.com/contracts/5.x/erc4626#defending_with_a_virtual_offset
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    /*************************/
    /*** Private Functions ***/
    /*************************/

    /// @dev Prefixes a string with a given prefix.
    function _prefix(
        string memory _p,
        string memory _str
    ) internal pure returns (string memory) {
        return string(abi.encodePacked(_p, _str));
    }
}

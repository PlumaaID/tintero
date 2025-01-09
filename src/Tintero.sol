// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {TinteroLoan} from "./TinteroLoan.sol";
import {TinteroLoanFactory} from "./TinteroLoan.factory.sol";
import {IPaymentCallback} from "./interfaces/IPaymentCallback.sol";

/// @title Tintero Vault
///
/// @notice An [ERC4626](https://docs.openzeppelin.com/contracts/5.x/erc4626) vault that receives
/// an ERC20 token in exchange for shares and allocates these assets towards funding Loan contracts
/// collateralized by tokenized ERC721 obligations.
///
/// The contract keeps track of the total assets in management by suming the total assets lent to
/// Loan contracts and the total assets held by the vault, allowing owners to withdraw their assets
/// at any time unless the vault does not have enough assets to cover the withdrawal (i.e. everything is
/// lent out).
///
/// == Concepts
///
/// - **Shares**: The vault's shares represent the ownership of the vault's assets. They can be
///   redeemed for the underlying assets if the vault has enough liquidity. They appreciate in value
///   as the vault's assets grow when Loan contracts are paid back.
/// - **Assets**: The vault's assets are the ERC20 tokens lent to Loan contracts. They are used to
///   fund Loan contracts and are returned to the vault plus interests when the Loan contracts are
///   paid back.
/// - **Loans**: Loan contracts are created by the vault and have a list of ERC721-backed payments.
/// - **Tranches**: A tranche is a collection of Loan payments from whose payments are sent to a tranche
///   recipient.
/// - **Payments**: A payment has a principal amount in ERC20 tokens that is due at the end of the maturity
///   period and defaults after the grace period. Each one is backed by an ERC721 token.
///
/// == Requesting a Loan
///
/// Any user can permissionlessly request a Loan by calling `requestLoan`. The Loan contract is created
/// by the vault and the Loan contract address is added to the vault's list of authorized Loans. Must
/// be funded by the vault by calling `fundN`.
///
/// == Vault Management
///
/// The vault is managed by an access manager instance that controls the permissions of critical
/// vault's functions. These functions include:
///
/// - `pushPayments`: Adds a list of payments to a Loan contract.
/// - `pushTranches`: Adds a list of tranches to a Loan contract.
/// - `fundN`: Funds `n` payments from a Loan contract.
/// - `repossess`: Repossess a range of payments from a Loan contract and cancels it. The Vault will
///   receive the ERC721 tokens and will cancel the tracked assets lent (absorbing the loss).
contract Tintero is ERC4626, TinteroLoanFactory, IPaymentCallback {
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
        ERC20(_prefix("Tinted ", asset_.name()), _prefix("t", asset_.symbol()))
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
    /// This is the minimum between the owner's max withdrawable assets and the vault's asset balance.
    function maxWithdraw(address owner) public view override returns (uint256) {
        IERC20Metadata asset_ = IERC20Metadata(asset());

        return
            Math.min(
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

    /**********************/
    /*** Loan Functions ***/
    /**********************/

    /// @dev Debits an outstanding principal from a Loan contract.
    /// Must be called by the Loan contract when a payment is either:
    ///
    /// - Repaid (value is accrued through interest)
    /// - Repossesses (value is lost)
    function onDebit(uint256 principal) external {
        address loan = msg.sender;
        if (!isLoan(loan)) revert OnlyAuthorizedLoan();
        _lentTo[loan] -= principal;
        _totalAssetsLent -= principal;
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
            collateralCollection_,
            beneficiary_,
            defaultThreshold_,
            payments_,
            collateralTokenIds_,
            salt
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

    /// @dev Adds a list of tranches to a Loan contract. Calls Loan#pushTranches.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    function pushTranches(
        TinteroLoan loan,
        uint96[] calldata paymentIndexes,
        address[] calldata recipients
    ) external restricted {
        if (!isLoan(address(loan))) revert OnlyAuthorizedLoan();

        loan.pushTranches(paymentIndexes, recipients);
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
        loan.repossess(start, end);
        // onERC721Received will update _lentTo and _totalAssetsLent
        assert(_lentTo[loan_] == 0);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /// @dev Virtual offset to defend against inflation attacks.
    /// See https://docs.openzeppelin.com/contracts/5.x/erc4626#defending_with_a_virtual_offset
    function _decimalsOffset() internal pure virtual override returns (uint8) {
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IERC4626, ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {AccessManaged} from "@openzeppelin/contracts/access/manager/AccessManaged.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {TinteroLoanFactory} from "./TinteroLoan.factory.sol";
import {ITinteroLoan} from "./interfaces/ITinteroLoan.sol";
import {ITinteroVault} from "./interfaces/ITinteroVault.sol";

/// @title Tintero Vault
///
/// @notice An [ERC4626](https://docs.openzeppelin.com/contracts/5.x/erc4626) vault that receives
/// an ERC20 token in exchange for shares and allocates these assets towards funding Loan contracts
/// collateralized by tokenized ERC721 obligations. Idle capital is delegated to other addresses to
/// maximize the yield of the vault's assets.
///
/// The contract keeps track of the total assets in management by suming the total assets lent to
/// Loan contracts and the total assets held by the vault, allowing owners to withdraw their assets
/// at any time unless the vault does not have enough assets to cover the withdrawal (i.e. everything is
/// lent out or delegated).
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
/// - `askDelegation`: Takes assets from the vault to use them in other protocols to maximize the
///   yield of the vault's assets.
/// - `pushTranches`: Adds a list of tranches to a Loan contract.
/// - `fundN`: Funds `n` payments from a Loan contract.
/// - `repossess`: Repossess a range of payments from a Loan contract and cancels it. The Vault will
///   receive the ERC721 tokens and will cancel the tracked assets lent (absorbing the loss).
/// - `upgradeLoan`: Upgrades a Loan contract to a new implementation. Allows renegotiating the terms
///   of the Loan contract.
///
/// == KYC and Accredited Investors
///
/// The `mint` and `deposit` functions are restricted to accredited investors that require a KYC check
/// before providing liqudity. However, the `withdraw` and `redeem` functions are permissionless, so
/// investors can withdraw their assets at any time as long as the vault has enough liquidity.
///
/// @author Ernesto García
///
/// @custom:security-contact security@plumaa.id
contract TinteroVault is ITinteroVault, TinteroLoanFactory, ERC4626 {
    using SafeERC20 for IERC20Metadata;
    using EnumerableSet for EnumerableSet.AddressSet;

    // Invariant: _totalAssetsLent == sum(_lentTo)
    uint256 private _totalAssetsDelegated;
    mapping(address delegate => uint256 assets) private _delegatedTo;
    uint256 private _totalAssetsLent;
    mapping(address loan => uint256 assets) private _lentTo;
    EnumerableSet.AddressSet private _loans;

    /// @dev Reverts if the provided address is not a loan managed by this vault.
    modifier onlyLoan(address loan) {
        if (!isLoan(loan)) revert OnlyManagedLoan();
        _;
    }

    /// @dev Constructor for Tintero Vault.
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

    /*********************/
    /*** Delegate View ***/
    /*********************/

    /// @dev The total amount of idle assets delegated.
    function totalAssetsDelegated() public view returns (uint256) {
        return _totalAssetsDelegated;
    }

    /// @dev The total amount of assets delegated to an address.
    function delegatedTo(address delegate) public view returns (uint256) {
        return _delegatedTo[delegate];
    }

    /*****************/
    /*** Loan View ***/
    /*****************/

    /// @dev The total amount of assets lent to Loan contracts.
    function totalAssetsLent() public view returns (uint256) {
        return _totalAssetsLent;
    }

    /// @dev The total amount of assets lent to a Loan contract.
    function lentTo(address loan) public view returns (uint256) {
        return _lentTo[loan];
    }

    /// @dev Whether a Loan contract is managed by this vault.
    function isLoan(address loan) public view returns (bool) {
        return _loans.contains(loan);
    }

    /********************/
    /*** ERC4626 View ***/
    /********************/

    /// @inheritdoc ERC4626
    function totalAssets()
        public
        view
        override(ERC4626, IERC4626)
        returns (uint256)
    {
        return super.totalAssets() + _totalAssetsLent + _totalAssetsDelegated;
    }

    /// @dev The maximum amount of assets that can be withdrawn.
    /// This is the minimum between the owner's max withdrawable assets and the vault's asset balance.
    function maxWithdraw(
        address owner
    ) public view override(ERC4626, IERC4626) returns (uint256) {
        IERC20Metadata asset_ = IERC20Metadata(asset());

        return
            Math.min(
                super.maxWithdraw(owner), // Max owner withdrawable assets
                asset_.balanceOf(address(this)) // Total available vault's asset balance
            );
    }

    /// @dev The maximum amount of shares that can be redeemed.
    /// This is the minimum between the owner's max redeemable shares and the vault's asset balance.
    function maxRedeem(
        address owner
    ) public view override(ERC4626, IERC4626) returns (uint256) {
        IERC20Metadata asset_ = IERC20Metadata(asset());
        return
            Math.min(
                super.maxRedeem(owner), // Max owner redeemable shares
                convertToShares(asset_.balanceOf(address(this))) // Max amount of shares redeemable for vault's asset balance
            );
    }

    /*************************/
    /*** Investor External ***/
    /*************************/

    /// @dev Deposit assets. Restricted to accredited investors.
    function deposit(
        uint256 assets,
        address receiver
    ) public override(ERC4626, IERC4626) restricted returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /// @dev Mints shares. Restricted to accredited investors.
    function mint(
        uint256 shares,
        address receiver
    ) public override(ERC4626, IERC4626) restricted returns (uint256) {
        return super.mint(shares, receiver);
    }

    /*************************/
    /*** Delegate External ***/
    /*************************/

    /// @dev Delegates assets to an address.
    function askDelegation(uint256 amount) external restricted {
        _delegatedTo[msg.sender] += amount;
        _totalAssetsDelegated += amount;
        IERC20Metadata(asset()).safeTransfer(msg.sender, amount);
        emit DelegateAssets(msg.sender, amount);
    }

    /// @dev Refunds delegated assets from an address.
    function refundDelegation(uint256 amount) external {
        address delegate = msg.sender;
        _refundDelegation(delegate, amount);
        IERC20Metadata(asset()).safeTransferFrom(
            delegate,
            address(this),
            amount
        );
    }

    /// @dev Forces the vault to take back delegated assets from a delegate if they deposit them back.
    function forceRefundDelegation(address delegate, uint256 amount) external {
        _refundDelegation(delegate, amount);
        _burn(delegate, Math.min(convertToShares(amount), balanceOf(delegate)));
    }

    /*********************/
    /*** Loan External ***/
    /*********************/

    /// @dev Creates a new instance of a Loan contract with the provided parameters.
    ///
    /// Requirements:
    ///
    /// - The loan MUST NOT have been created.
    /// - Those of SafeERC20.safeIncreaseAllowance.
    /// - Those of Loan#pushPayments.
    function requestLoan(
        address collateralCollection,
        address beneficiary,
        uint24 defaultThreshold,
        PaymentLib.Payment[] calldata payments,
        uint256[] calldata collateralTokenIds,
        bytes32 salt
    ) external {
        address predicted = _deployLoan(
            collateralCollection,
            beneficiary,
            defaultThreshold,
            salt
        );
        if (!_loans.add(predicted)) revert DuplicatedLoan();
        _pushPayments(ITinteroLoan(predicted), collateralTokenIds, payments);
    }

    /// @dev Adds a list of payments to a Loan contract. Calls Loan#pushPayments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    /// - Those of SafeERC20.safeIncreaseAllowance.
    /// - Those of Loan#pushPayments.
    function pushPayments(
        ITinteroLoan loan,
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payments
    ) external onlyLoan(address(loan)) {
        _pushPayments(loan, collateralTokenIds, payments);
    }

    /// @dev Debits an outstanding principal from a Loan contract.
    /// Must be called by the Loan contract when a payment is either:
    ///
    /// - Repaid (value is accrued through interest)
    /// - Repossessed (value is lost)
    function onDebit(uint256 principal) external onlyLoan(msg.sender) {
        _lentTo[msg.sender] -= principal;
        _totalAssetsLent -= principal;
    }

    /******************/
    /*** Management ***/
    /******************/

    /// @dev Adds a list of tranches to a Loan contract. Calls Loan#pushTranches.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    /// - Those of Loan#pushTranches.
    function pushTranches(
        ITinteroLoan loan,
        uint96[] calldata paymentIndexes,
        address[] calldata recipients
    ) external restricted onlyLoan(address(loan)) {
        loan.pushTranches(paymentIndexes, recipients);
    }

    /// @dev Funds `n` payments from a Loan contract. Calls Loan#fundN.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    ///
    /// NOTE: The manager MUST ensure that tranches are paid back to the vault in
    /// a way that covers at least the principal lent. Otherwise, the vault will
    /// loose value even if the Loan contract is paid back.
    function fundN(
        ITinteroLoan loan,
        uint256 n
    ) external restricted onlyLoan(address(loan)) {
        // Reentrancy would be possible if `fundN` allows for it.
        // However, `fundN` interacts with the asset contract, which has no callback mechanism.
        uint256 totalPrincipalFunded = loan.fundN(n);
        _lentTo[address(loan)] += totalPrincipalFunded;
        _totalAssetsLent += totalPrincipalFunded;
    }

    /// @dev Repossess a range of payments from a Loan contract. Calls Loan#repossess.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    /// - The receiver must implement IERC721Receiver to receive the collateral (if contract).
    /// - Those of Loan#repossess.
    function repossess(
        ITinteroLoan loan,
        uint256 start,
        uint256 end,
        address receiver
    ) external restricted onlyLoan(address(loan)) {
        loan.repossess(start, end, receiver);
    }

    /// @dev Upgrades a Loan contract to a new implementation. Calls Loan#upgradeLoan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be created by this vault.
    /// - Those of Loan#upgradeLoan.
    function upgradeLoan(
        ITinteroLoan loan,
        address newImplementation,
        bytes calldata data
    ) external restricted onlyLoan(address(loan)) {
        loan.upgradeLoan(newImplementation, data);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /// @dev Refunds delegated assets from an address.
    function _refundDelegation(address delegate, uint256 amount) internal {
        _delegatedTo[delegate] -= amount; // Will overflow if the delegate refunds more than delegated
        _totalAssetsDelegated -= amount;
        emit DelegateRefunded(delegate, amount);
    }

    /// @dev Pushes a list of payments to a Loan contract and increases its allowance accordingly.
    function _pushPayments(
        ITinteroLoan loan,
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payments
    ) internal {
        // State is consistent at this point.
        // Although reentrancy is possible from the loan, it's not an issue.
        uint256 principalRequested = loan.pushPayments(
            collateralTokenIds,
            payments
        );
        IERC20Metadata(asset()).safeIncreaseAllowance(
            address(loan),
            principalRequested
        );
    }

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

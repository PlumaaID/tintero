// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {PaymentLib} from "../utils/PaymentLib.sol";
import {ITinteroLoan} from "./ITinteroLoan.sol";

/// @dev Interface for an ERC4626 that manages ITinteroLoan contracts.
///
/// The vault's assets are either lent to Loan contracts or delegated to other addresses
/// to maximize the utilization of the assets.
interface ITinteroVault is IERC4626 {
    /*********************/
    /*** Delegate View ***/
    /*********************/

    /// @dev The total amount of idle assets delegated.
    function totalAssetsDelegated() external view returns (uint256);

    /// @dev The total amount of idle assets delegated to an address.
    function delegatedTo(address delegate) external view returns (uint256);

    /*****************/
    /*** Loan View ***/
    /*****************/

    /// @dev The total amount of assets lent to Loan contracts.
    function totalAssetsLent() external view returns (uint256);

    /// @dev The total amount of assets lent to a Loan contract.
    function lentTo(address loan) external view returns (uint256);

    /// @dev Whether a Loan contract is managed by this vault.
    function isLoan(address loan) external view returns (bool);

    /*************************/
    /*** Delegate External ***/
    /*************************/

    /// @dev Delegates assets to an address.
    function askDelegation(uint256 amount) external;

    /// @dev Refunds delegated assets from an address.
    function refundDelegation(uint256 amount) external;

    // @dev Forces the vault to take back delegated assets from a delegate if they deposit them back.
    function forceRefundDelegation() external;

    /*********************/
    /*** Loan External ***/
    /*********************/

    /// @dev Creates a new instance of a Loan contract with the provided parameters.
    function requestLoan(
        address collateralCollection,
        address beneficiary,
        uint24 defaultThreshold,
        PaymentLib.Payment[] calldata payments,
        uint256[] calldata collateralTokenIds,
        bytes32 salt
    ) external;

    /// @dev Adds a list of payments to a Loan contract. Calls Loan#pushPayments.
    function pushPayments(
        ITinteroLoan loan,
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payments
    ) external;

    /// @dev Debits an outstanding principal from a Loan contract.
    function onDebit(uint256 principal) external;

    /******************/
    /*** Management ***/
    /******************/

    /// @dev Adds a list of tranches to a Loan contract. Calls Loan#pushTranches.
    function pushTranches(
        ITinteroLoan loan,
        uint96[] calldata paymentIndexes,
        address[] calldata recipients
    ) external;

    /// @dev Funds `n` payments from a Loan contract. Calls Loan#fundN.
    function fundN(ITinteroLoan loan, uint256 n) external;

    /// @dev Repossess a range of payments from a Loan contract. Calls Loan#repossess.
    function repossess(
        ITinteroLoan loan,
        uint256 start,
        uint256 end,
        address receiver
    ) external;

    /// @dev Upgrades a Loan contract to a new implementation. Calls Loan#upgradeLoan.
    function upgradeLoan(
        ITinteroLoan loan,
        address newImplementation,
        bytes calldata data
    ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentLib} from "../utils/PaymentLib.sol";
import {LoanState} from "./ITinteroLoan.types.sol";

/// @dev Errors for the ERC721 Collateral Loan.
interface ITinteroLoanErrors {
    /// @dev The loan is already funded so it can't be funded again.
    error PaymentFunded(uint256 tokenId);

    /// @dev The payment is already matured so it can't be added to the loan.
    error PaymentMatured(uint256 tokenId);

    /// @dev The payment is already defaulted so it can't be added to the loan.
    error DuplicatedCollateral(uint256 tokenId);

    /// @dev The payment is already defaulted so it can't be added to the loan.
    error UnorderedPayments();

    /// @dev Only the liquidity provider can perform the operation.
    error OnlyLiquidityProvider();

    /// @dev The beneficiary address is not valid.
    error InvalidBeneficiary();

    /// @dev Only the beneficiary can perform the operation.
    error OnlyBeneficiary();

    /// @dev The payments array doesn't match the collateral tokenIds array.
    error MismatchedPaymentCollateralIds();

    /// @dev The paymentIndex array doesn't match the tranche recipients array.
    error MismatchedTranchePaymentIndexRecipient();

    /// @dev The tranche paymentIndex are not strictly increasing.
    error UnincreasingTranchePaymentIndex();

    /// @dev There are more tranches than payments
    error TooManyTranches();

    /// @dev The current tranches do not include all payments.
    error UntranchedPayments();

    /// @dev The current state of the loan is not the required for performing an operation.
    /// The `expectedStates` is a bitmap with the bits enabled for each LoanState enum position
    /// counting from right to left.
    ///
    /// NOTE: If `expectedState` is `bytes32(0)`, any state is expected.
    error UnexpectedLoanState(LoanState current, bytes32 expectedStates);
}

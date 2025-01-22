// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {PaymentLib} from "../utils/PaymentLib.sol";

import {ITinteroLoanEvents} from "./ITinteroLoan.events.sol";
import {ITinteroLoanErrors} from "./ITinteroLoan.errors.sol";
import {LoanState} from "./ITinteroLoan.types.sol";
import {IPaymentCallback} from "./IPaymentCallback.sol";

/// @title ERC721 Collateral Loan Interface
///
/// @notice Interface for a loan contract that uses an ERC721 token as collateral.
/// The loan is funded with an ERC20 token and structured in a series of payments and
/// tranches.
///
/// ```mermaid
/// stateDiagram-v2
///     state CREATED
///     state CANCELED
///     state FUNDING
///     state ONGOING
///     state DEFAULTED
///     state REPOSSESSED
///     state PAID
///
///     [*] --> CREATED
///     CREATED --> FUNDING: calling fundN(...)
///     FUNDING --> ONGOING: calling fundN(...)
///     CREATED --> ONGOING: calling fundN(...)
///     CREATED --> CANCELED: calling withdrawPaymentCollateral()
///     ONGOING --> DEFAULTED: after defaultThreshold() payments are missed
///     ONGOING --> PAID: calling repayN(...)
///     DEFAULTED --> REPOSSESSED: calling recall(...)
///     DEFAULTED --> ONGOING: calling repayN(...)
///     DEFAULTED --> PAID: calling repayN(...)
/// ```
interface ITinteroLoan is ITinteroLoanEvents, ITinteroLoanErrors {
    /// @dev Address of the ERC20 token lent.
    function lendingAsset() external view returns (IERC20);

    /// @dev Address of the ERC721 token used as collateral.
    function collateralAsset() external view returns (ERC721Burnable);

    /// @dev Address of the liquidity provider funding the loan.
    function liquidityProvider() external view returns (IPaymentCallback);

    /// @dev Get the index at which the tranche starts and its recipient.
    /// A tranche is a collection of payments from [paymentIndex ?? 0, nextPaymentIndex)
    function tranche(
        uint256 trancheIndex
    ) external view returns (uint96 paymentIndex, address recipient);

    /// @dev Get the index of the current tranche.
    function currentTrancheIndex() external view returns (uint256);

    /// @dev Get the current tranche.
    function currentTranche()
        external
        view
        returns (uint96 paymentIndex, address recipient);

    /// @dev Total tranches in the loan.
    function totalTranches() external view returns (uint256);

    /// @dev Get payment details. A Payment is a struct with a principal and interest terms.
    function payment(
        uint256 index
    )
        external
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory);

    /// @dev Get the index of the current payment yet to be repaid.
    function currentPaymentIndex() external view returns (uint256);

    /// @dev Get the payment at which the loan is currently at and its collateral tokenId.
    function currentPayment()
        external
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory);

    /// @dev Get the total number of payments.
    function totalPayments() external view returns (uint256);

    /// @dev Get the index of the current payment yet to be funded.
    function currentFundingIndex() external view returns (uint256);

    /// dev Get the current payment yet to be funded.
    function currentPaymentFunding()
        external
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory);

    /// @dev Address of the beneficiary of the loan.
    function beneficiary() external view returns (address);

    /// @dev Amount of missed payments at which the loan is defaulted.
    function defaultThreshold() external view returns (uint256);

    /// @dev Get the current state of the loan.
    function state() external view returns (LoanState);

    /// @dev Adds a list of payments to the loan.
    ///
    /// Requirements:
    ///
    /// - The caller MUST be the liquidity provider.
    /// - The loan MUST be in CREATED state.
    /// - The collateral tokenIds and payments arrays MUST have the same length.
    /// - The payments MUST be ordered by maturity date.
    /// - The payments MUST NOT have matured.
    /// - The collateral tokenIds MUST NOT have been added before.
    /// - The collateralTokenIds MUST exist.
    /// - The owner of each collateral tokenId MUST have approved this contract
    ///   to transfer it (if not the contract itself).
    ///
    /// Effects:
    ///
    /// - The `totalPayments` is incremented by the length of the payments array.
    /// - The `collateralTokenIds` are transferred to this contract.
    /// - The `payment` function will return the added payments at their corresponding
    ///   indexes starting at `totalPayments`.
    /// - Emits a `CreatedPayment` event for each payment added.
    function pushPayments(
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payments
    ) external returns (uint256 principalRequested);

    /// @dev Adds a list of tranches to the loan.
    ///
    /// Requirements:
    ///
    /// - The caller MUST be the liquidity provider.
    /// - The loan MUST be in CREATED state.
    /// - The tranchePaymentIndexes and trancheRecipients arrays MUST have the same length.
    /// - The tranche indexes MUST be strictly increasing.
    /// - The total number of tranches MUST be less than the total number of payments.
    ///
    /// Effects:
    ///
    /// - The `totalTranches` is incremented by the length of the tranches array.
    /// - The `tranche` function will return the added tranches at their corresponding
    ///   indexes starting at `totalTranches`.
    /// - The tranches are added to the loan.
    /// - Emits a `CreatedTranche` event for each tranche added.
    function pushTranches(
        uint96[] calldata paymentIndexes,
        address[] calldata recipients
    ) external;

    /// @dev Funds `n` payments from the loan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED or FUNDING state.
    /// - Tranches MUST include all payments.
    /// - The caller MUST have enough funds to fund the payments
    /// - This contract mus have been approved to transfer the principal
    ///   amount from the caller.
    ///
    /// Effects:
    ///
    /// - Moves to FUNDING state
    /// - Moves to ONGOING state if all payments are funded.
    /// - The `currentFundingIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the funded payments is transferred from the liquidity provider to the beneficiary.
    /// - Emits a `FundedPayment` event for each payment funded.
    function fundN(uint256 n) external;

    /// @dev Withdraws the collateral to the beneficiary.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED or CANCELED state.
    /// - Each payment collateral MUST be owned by this contract.
    /// - The caller MUST be the beneficiary.
    ///
    /// Effects:
    ///
    /// - Moves to CANCELED state.
    /// - Each payment collateral is transferred to the beneficiary.
    /// - Emits a `WithdrawnPayment` event for each payment withdrawn.
    function withdrawPaymentCollateral(uint256 start, uint256 end) external;

    /// @dev Same as `repayN(0, collateralReceiver)`.
    function repayCurrent(address collateralReceiver) external;

    /// @dev Repays the current loan and `n` future payments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in ONGOING or DEFAULTED state.
    /// - The sender MUST have enough funds to repay the principal of the specified payments
    /// - The sender MUST have approved this contract to transfer the principal amount
    /// - The collateral MUST be owned by this contract.
    ///
    /// Effects:
    ///
    /// - Moves to ONGOING if paid until below the default threshold.
    /// - Moves to PAID state if all payments are repaid.
    /// - The `currentPaymentIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the repaid payments is transferred from the sender to the receiver of each payment tranche
    /// - The collateral is transferred to the collateralReceiver if provided, otherwise it is burned.
    /// - Emits a `RepaidPayment` event for each payment repaid.
    function repayN(uint256 n, address collateralReceiver) external;

    /// @dev Repossess the collateral from payments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in DEFAULTED or REPOSSESSED state.
    /// - The caller MUST be the liquidity provider.
    /// - The collateral MUST be owned by this contract.
    /// - The receiver MUST implement IERC721Receiver to receive the collateral.
    ///
    /// Effects:
    ///
    /// - Moves to REPOSSESSED state.
    /// - The collateral is transferred to the receiver.
    /// - Emits a `RepossessedPayment` event for each payment repossessed.
    function repossess(uint256 start, uint256 end, address receiver) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {PaymentLib} from "../utils/PaymentLib.sol";

import {ITinteroLoanEvents} from "./ITinteroLoan.events.sol";
import {ITinteroLoanErrors} from "./ITinteroLoan.errors.sol";
import {LoanState} from "./ITinteroLoan.types.sol";

/// @title ERC721 Collateral Loan Interface
///
/// @notice Interface for a loan contract that uses an ERC721 token as collateral.
/// The loan is funded with an ERC20 token and structured in a series of payments.
///
/// ```mermaid
/// stateDiagram-v2
///     state CREATED
///     state CANCELED
///     state FUNDING
///     state FUNDED
///     state DEFAULTED
///     state REPOSSESSED
///     state PAID

///     [*] --> CREATED
///     CREATED --> FUNDING: calling fundN(...)
///     FUNDING --> FUNDED: calling fundN(...)
///     CREATED --> FUNDED: calling fundN(...)
///     CREATED --> CANCELED: calling withdrawPaymentCollateral()
///     FUNDED --> DEFAULTED: after defaultThreshold() payments are missed
///     FUNDED --> PAID: calling repayN(...)
///     DEFAULTED --> REPOSSESSED: calling recall(...)
///     DEFAULTED --> FUNDED: calling repayN(...)
///     DEFAULTED --> PAID: calling repayN(...)
/// ```
interface ITinteroLoan is ITinteroLoanEvents, ITinteroLoanErrors {
    /// @dev Address of the ERC20 token lent.
    function lendingAsset() external view returns (IERC20);

    /// @dev Address of the ERC721 token used as collateral.
    function collateralAsset() external view returns (ERC721Burnable);

    /// @dev Address of the liquidity provider funding the loan.
    function liquidityProvider() external view returns (address);

    /// @dev Get payment details.
    function payment(
        uint256 index
    )
        external
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory);

    /// @dev Get the index of the current payment yet to be repaid.
    function currentPaymentIndex() external view returns (uint256);

    /// @dev Get the index of the current payment yet to be funded.
    function currentFundingIndex() external view returns (uint256);

    /// @dev Get the payment at which the loan is currently at and its collateral tokenId.
    function currentPayment()
        external
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory);

    /// @dev Get the total number of payments.
    function totalPayments() external view returns (uint256);

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
    ) external;

    /// @dev Funds `n` payments from the loan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED or FUNDING state.
    /// - The liquidityProvider MUST have enough funds to repay the principal of the current payment
    /// - This contract mus have been approved to transfer the principal
    ///   amount from the liquidity provider.
    /// - Emits a `FundedPayment` event for each payment funded.
    ///
    /// Effects:
    ///
    /// - Moves to FUNDING state
    /// - Moves to FUNDED state if all payments are funded.
    /// - The `currentFundingIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the funded payments is transferred from the liquidity provider to the beneficiary.
    function fundN(uint256 n) external returns (uint256);

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
    /// - The loan MUST be in FUNDED or DEFAULTED state.
    /// - The beneficiary MUST have enough funds to repay the principal of the current payment
    /// - The beneficiary MUST have approved this contract to transfer the principal amount
    ///
    /// Effects:
    ///
    /// - Moves to FUNDED if paid until below the default threshold.
    /// - Moves to PAID state if all payments are repaid.
    /// - The `currentPaymentIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the repaid payments is transferred from the beneficiary to the liquidity provider.
    /// - The collateral is transferred to the collateralReceiver if provided, otherwise it is burned.
    /// - Emits a `RepaidPayment` event for each payment repaid.
    function repayN(uint256 n, address collateralReceiver) external;

    /// @dev Repossess the collateral from payments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in DEFAULTED or REPOSSESSED state.
    /// - The caller MUST be the liquidity provider.
    ///
    /// Effects:
    ///
    /// - Moves to REPOSSESSED state.
    /// - The collateral is transferred back to the liquidity provider.
    /// - Emits a `RepossessedPayment` event for each payment repossessed.
    function repossess(uint256 start, uint256 end) external;
}

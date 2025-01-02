// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/interfaces/IERC721.sol";
import {PaymentLib} from "../utils/PaymentLib.sol";

/// @title ERC721 Collateral Loan Interface
///
/// @notice Interface for a loan contract that uses an ERC721 token as collateral.
/// The loan is funded with an ERC20 token and structured in a series of payments.
///
/// ```mermaid
/// stateDiagram-v2
///     state CREATED
///     state CANCELED
///     state FUNDED
///     state DEFAULTED
///
///     [*] --> CREATED
///     CREATED --> FUNDED: calling fundN(...)
///     CREATED --> CANCELED: calling withdrawPaymentCollateral()
///     FUNDED --> DEFAULTED: after defaultThreshold() payments are missed
///     FUNDED --> PAID: calling repayN(...)
///     DEFAULTED --> REPOSSESSED: calling repossess(...)
///     DEFAULTED --> FUNDED: calling repayN(...)
///     DEFAULTED --> PAID: calling repayN(...)
/// ```
interface IERC721CollateralLoan {
    /// @dev Emitted when a payment is
    event FundedPayment(
        uint256 indexed index,
        uint256 indexed tokenId,
        uint256 principal
    );

    /// @dev Emitted when the collateral is withdrawn by the beneficiary.
    event WithdrawnPayment(
        uint256 indexed index,
        uint256 indexed tokenId,
        uint256 principal
    );

    /// @dev Emitted when a loan payment is repaid.
    event RepaidPayment(
        uint256 indexed index,
        uint256 indexed tokenId,
        uint256 principal,
        uint256 interest,
        uint256 premiumInterest
    );

    /// @dev Emitted when a loan payment is repossessed.
    event RepossessedPayment(
        uint256 indexed index,
        uint256 indexed tokenId,
        uint256 principal
    );

    /// @dev The possible states of a loan.
    enum LoanState {
        CREATED,
        CANCELED,
        FUNDED,
        DEFAULTED,
        REPOSSESSED,
        PAID
    }

    /// @dev The payment is already matured so it can't be added to the loan.
    error PaymentMatured(uint256 tokenId);

    /// @dev The payment is already defaulted so it can't be added to the loan.
    error DuplicatedCollateral(uint256 tokenId);

    /// @dev The payment is already defaulted so it can't be added to the loan.
    error UnorderedPayments();

    /// @dev Only the liquidity provider can perform the operation.
    error OnlyLiquidityProvider();

    /// @dev Only the beneficiary can perform the operation.
    error OnlyBeneficiary();

    /// @dev The provided address is the zero address.
    error ZeroAddress();

    /// @dev The payments array doesn't match the collateral tokenIds array.
    error MismatchedPaymentCollateralIds();

    /// @dev The current state of the loan is not the required for performing an operation.
    /// The `expectedStates` is a bitmap with the bits enabled for each LoanState enum position
    /// counting from right to left.
    ///
    /// NOTE: If `expectedState` is `bytes32(0)`, any state is expected.
    error UnexpectedLoanState(LoanState current, bytes32 expectedStates);

    /// @dev Address of the ERC20 token lent.
    function lendingAsset() external view returns (IERC20);

    /// @dev Address of the ERC721 token used as collateral.
    function collateralAsset() external view returns (IERC721);

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

    /// @dev Get the payment at which the loan is currently at.
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

    ///

    /// @dev Add payments to the loan. MUST be in CREATED state.
    function pushPayments(
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payments
    ) external;

    /// @dev Funds `n` payments from the loan loan. MUST be in CREATED state.
    function fundN(uint256 n) external returns (uint256);

    /// @dev Withdraws the collateral to the beneficiary. MUST be in CREATED or CANCELED state. Cancels the loan.
    function withdrawPaymentCollateral(uint256 start, uint256 end) external;

    /// @dev Repays the current loan payment. MUST be in FUNDED or DEFAULTED state.
    function repayCurrent() external;

    /// @dev Repays the current loan and `n` future payments. MUST be in FUNDED or DEFAULTED state.
    function repayN(uint256 n) external;

    /// @dev Repossess the collateral from payments. MUST be in DEFAULTED or REPOSSESSED state.
    function repossess(uint256 start, uint256 end) external;
}

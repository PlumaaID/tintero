// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {ITinteroLoan} from "./interfaces/ITinteroLoan.sol";
import {TinteroLoanView} from "./TinteroLoan.view.sol";
import {TinteroLoanStorage} from "./TinteroLoan.storage.sol";
import {LoanState} from "./interfaces/ITinteroLoan.types.sol";

/// @title ERC721 Collateral Loan Interface
///
/// @notice Loan that uses an ERC721 token as collateral. The loan is funded with
/// an ERC20 token and structured in a series of payments and tranches they belong to.
///
/// This contract behaves as a state machine with the following states:
///
/// - CREATED: The loan has been initialized and payments or tranches are being added.
/// - CANCELED: The loan has been canceled and the collateral is being withdrawn.
/// - FUNDING: The loan is being funded by the liquidity provider.
/// - ONGOING: The loan has been funded and the payments are being repaid.
/// - DEFAULTED: The loan has defaulted and the collateral can be repossessed.
/// - REPOSSESSED: The collateral is being repossessed by the liquidity provider.
/// - PAID: The loan has been fully repaid.
///
/// == Concepts
///
/// - Payments: A payment is a structure that represents a payment to be made back to the loan.
///   Each payment has a principal amount and an interest rate that is accrued over time in a
///   linear fashion. A premium rate is added to the interest rate after the payment is due (at maturity).
/// - Tranches: A tranche is a collection of payments that have the same recipient. They are used
///   to sell parts of the loan to different investors.
/// - Collateral: The collateral is an ERC721 token that is used to back the payments. A payment's
///   collateral can be repossessed if the loan defaults after a default threshold.
///
/// NOTE: Users must approve this contract to transfer their ERC-721 tokens used as collateral.
/// This may allow a malicious actor to transfer request a loan and transferring their tokens
/// to this contract unexpectedly. For those cases, the original owner can retake their collateral
/// with the `withdrawPaymentCollateral` function.
///
/// @author Ernesto García
///
/// @custom:security-contact security@plumaa.id
contract TinteroLoan is Initializable, UUPSUpgradeable, TinteroLoanView {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using PaymentLib for PaymentLib.Payment;
    using Checkpoints for Checkpoints.Trace160;
    using SafeCast for uint256;

    /// @dev Reverts if the caller is not the loan's liquidity provider
    modifier onlyLiquidityProvider() {
        if (msg.sender != address(liquidityProvider()))
            revert OnlyLiquidityProvider();
        _;
    }

    /// @dev Reverts if the caller is not the loan's beneficiary
    modifier onlyBeneficiary() {
        if (msg.sender != beneficiary()) revert OnlyBeneficiary();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the loan with the provided parameters.
    ///
    /// @param liquidityProvider_ The address funding the loan.
    /// @param collateralAsset_ The ERC721 token used as collateral.
    /// @param beneficiary_ The address to receive the principal once funded.
    /// @param defaultThreshold_ The number of missed payments at which the loan defaults.
    function initialize(
        address liquidityProvider_,
        address collateralAsset_,
        address beneficiary_,
        uint24 defaultThreshold_
    ) public initializer {
        if (beneficiary_ == address(0)) revert InvalidBeneficiary();
        LoanStorage storage $ = getTinteroLoanStorage();
        $.liquidityProvider = liquidityProvider_;
        $.collateralAsset = collateralAsset_;
        $.beneficiary = beneficiary_;
        $.defaultThreshold = defaultThreshold_;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

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
    /// - Emits a `PaymentCreated` event for each payment added.
    function pushPayments(
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payment_
    ) external onlyLiquidityProvider returns (uint256 principalRequested) {
        _validateStateBitmap(_encodeStateBitmap(LoanState.CREATED));
        return
            _validatePushPaymentsAndCollectCollateral(
                collateralTokenIds,
                payment_
            );
    }

    /// @dev Adds a list of tranches to the loan.
    ///
    /// Requirements:
    ///
    /// - The caller MUST be the liquidity provider.
    /// - The loan MUST be in CREATED state.
    /// - The paymentIndexes and recipients arrays MUST have the same length.
    /// - The tranche indexes MUST be strictly increasing.
    /// - The total number of tranches MUST be less than the total number of payments.
    ///
    /// Effects:
    ///
    /// - The `totalTranches` is incremented by the length of the tranches array.
    /// - The `tranche` function will return the added tranches at their corresponding
    ///   indexes starting at `totalTranches`.
    /// - The tranches are added to the loan.
    /// - Emits a `TrancheCreated` event for each tranche added.
    function pushTranches(
        uint96[] calldata paymentIndexes,
        address[] calldata recipients
    ) external onlyLiquidityProvider {
        _validateStateBitmap(_encodeStateBitmap(LoanState.CREATED));
        _validateAndPushTranches(paymentIndexes, recipients);
    }

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
    /// - Sets the `fundedAt` field of the funded payments to the current block timestamp.
    /// - Emits a `PaymentsFunded` event with the range of funded payments.
    function fundN(uint256 n) external returns (uint256 totalPrincipal) {
        if (n == 0) return 0; // No-op

        // Checks
        (uint256 lastPaymentIndex, ) = tranche(totalTranches() - 1); // Will overflow if totalTranches() == 0
        if (lastPaymentIndex != totalPayments()) revert UntranchedPayments();
        _validateStateBitmap(
            _encodeStateBitmap(LoanState.CREATED) |
                _encodeStateBitmap(LoanState.FUNDING)
        );

        // Effects
        totalPrincipal = _fundN(n);

        // Interactions
        // We tie funding to `msg.sender`, otherwise it enables arbitrary account draining if they approved the contract.
        lendingAsset().safeTransferFrom(
            address(msg.sender),
            beneficiary(),
            totalPrincipal
        );

        return totalPrincipal;
    }

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
    /// - Emits a `PaymentsWithdrawn` with the range of payments withdrawn
    function withdrawPaymentCollateral(
        uint256 start,
        uint256 end
    ) external onlyBeneficiary {
        LoanState state_ = _validateStateBitmap(
            _encodeStateBitmap(LoanState.CANCELED) |
                _encodeStateBitmap(LoanState.CREATED)
        );

        // Effects and Interactions
        _withdrawPaymentCollateral(state_, start, end);
    }

    /// @dev Same as `repayN(0, collateralReceiver)`.
    function repayCurrent(address collateralReceiver) external {
        repayN(0, collateralReceiver);
    }

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
    /// - Emits a `PaymentsRepaid` event with the range of repaid payments.
    function repayN(uint256 n, address collateralReceiver) public {
        // Checks
        _validateStateBitmap(
            _encodeStateBitmap(LoanState.ONGOING) |
                _encodeStateBitmap(LoanState.DEFAULTED)
        );

        // Effects
        uint256 start = currentPaymentIndex();
        uint256 end = Math.min(start + 1 + n, totalPayments());

        // Interactions
        _repay(start, end, collateralReceiver);
    }

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
    /// - Emits a `PaymentsRepossessed` event with the range of repossessed payments.
    function repossess(
        uint256 start,
        uint256 end,
        address receiver
    ) external onlyLiquidityProvider {
        LoanState state_ = _validateStateBitmap(
            _encodeStateBitmap(LoanState.DEFAULTED) |
                _encodeStateBitmap(LoanState.REPOSSESSED)
        );

        // Effects and Interactions
        _repossess(state_, start, end, receiver);
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    /// @dev Performs validations on the payments to be added to the loan.
    ///
    /// Requirements:
    ///
    /// - The collateral tokenIds and payments arrays MUST have the same length.
    /// - The payments MUST be ordered by maturity date.
    /// - The payments `fundedAt` field MUST be 0.
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
    /// - Emits a `PaymentCreated` event for each payment added.
    function _validatePushPaymentsAndCollectCollateral(
        uint256[] calldata collateralTokenIds_,
        PaymentLib.Payment[] calldata payments_
    ) internal returns (uint256) {
        uint256 paymentsLength = payments_.length;
        // Checks
        if (collateralTokenIds_.length != paymentsLength)
            revert MismatchedPaymentCollateralIds();

        uint256 totalPayments_ = totalPayments();
        uint256 latestMaturity = 0;

        if (totalPayments_ > 0) {
            latestMaturity = payment(totalPayments_ - 1).maturedAt();
        }

        // Checks and Effects
        uint256 principalRequested = 0;
        for (uint256 i = 0; i < paymentsLength; i++) {
            latestMaturity = _validatePushPayment(
                totalPayments_ + i,
                latestMaturity,
                collateralTokenIds_[i],
                payments_[i]
            );
            principalRequested += payments_[i].principal;
        }
        // Interactions
        ERC721Burnable asset = collateralAsset();
        for (uint256 i = 0; i < paymentsLength; i++)
            _collectCollateral(asset, collateralTokenIds_[i]);

        return principalRequested;
    }

    /// @dev Validates the tranches and adds them to the loan.
    ///
    /// Requirements:
    ///
    /// - The paymentIndexes and recipients arrays MUST have the same length.
    /// - The tranche indexes MUST be strictly increasing.
    /// - The total number of tranches MUST be less than the total number of payments.
    ///
    /// Effects:
    ///
    /// - The `totalTranches` is incremented by the length of the tranches array.
    /// - The `tranche` function will return the added tranches at their corresponding
    ///   indexes starting at `totalTranches`.
    /// - The tranches are added to the loan.
    /// - Emits a `TrancheCreated` event for each tranche added.
    function _validateAndPushTranches(
        uint96[] calldata paymentIndexes_,
        address[] calldata recipients_
    ) internal {
        uint256 paymentIndexesLength = paymentIndexes_.length;
        // Checks
        if (paymentIndexesLength != recipients_.length)
            revert MismatchedTranchePaymentIndexRecipient();

        // Effects
        LoanStorage storage $ = getTinteroLoanStorage();
        uint256 totalTranches_ = totalTranches();
        uint96 lastIndex = 0;
        for (uint256 i = 0; i < paymentIndexesLength; i++) {
            uint96 paymentIndex = paymentIndexes_[i];
            if (paymentIndex <= lastIndex)
                revert UnincreasingTranchePaymentIndex();
            lastIndex = paymentIndex;
            $._tranches.push(paymentIndex, uint160(recipients_[i]));
            emit TrancheCreated(
                totalTranches_ + i,
                paymentIndex,
                recipients_[i]
            );
        }

        if (totalTranches() > totalPayments()) revert TooManyTranches();
    }

    /// @dev Validates the payment and adds it to the loan.
    ///
    /// Requirements:
    ///
    /// - The payment `fundedAt` field MUST be 0.
    /// - The payment maturity date MUST NOT be before the latest maturity.
    /// - The payment MUST NOT have matured.
    /// - The collateral tokenId MUST not have been added before.
    ///
    /// Effects:
    ///
    /// - The `totalPayments` is incremented by 1.
    /// - The `payment` function will return the added `_payment` after the current `totalPayments`.
    /// - Emits a `PaymentCreated` event.
    function _validatePushPayment(
        uint256 i,
        uint256 latestMaturity,
        uint256 collateralTokenId,
        PaymentLib.Payment calldata payment_
    ) internal returns (uint256) {
        // Checks
        if (payment_.fundedAt != 0) revert PaymentFunded(collateralTokenId);
        uint256 maturedAt = payment_.maturedAt();
        if (maturedAt < latestMaturity) revert UnorderedPayments();
        if (
            payment_.matured() /* || payment_.defaulted() */ // Default is strictly higher or equal to maturity
        ) revert PaymentMatured(collateralTokenId);

        // Effects
        LoanStorage storage $ = getTinteroLoanStorage();
        if (!$.heldTokenIds.add(collateralTokenId))
            // Intentionally last check since it's also a side effect
            revert DuplicatedCollateral(collateralTokenId);
        $.payments.push(payment_);
        $.collateralTokenIds.push(collateralTokenId);
        emit PaymentCreated(i, collateralTokenId, payment_);
        return maturedAt;
    }

    /// @dev Checks if the tokenId is owned by this contract and transfers it to this contract otherwise.
    ///
    /// Requirements:
    ///
    /// - The collateralTokenIds MUST exist.
    /// - The owner of each collateral tokenId MUST have approved this contract
    ///   to transfer it (if not the contract itself).
    ///
    /// Effects:
    ///
    /// - The `collateralTokenIds` are transferred to this contract.
    function _collectCollateral(
        ERC721Burnable asset,
        uint256 tokenId
    ) internal {
        // Reverts if tokenId doesn't exist
        address assetOwner = asset.ownerOf(tokenId);
        if (assetOwner != address(this)) {
            // Reverts if the transfer fails
            // Intentionally not using `safeTransferFrom` given the recipient is this contract.
            asset.transferFrom(assetOwner, address(this), tokenId);
        }
    }

    /// @dev Funds `n` payments from the loan. Returns the total principal to fund.
    /// The `end` index is capped to the total number of payments.
    ///
    /// Effects:
    ///
    /// - Moves to FUNDING state
    /// - Moves to ONGOING state if all payments are funded.
    /// - The `currentFundingIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the funded payments is transferred from the liquidity provider to the beneficiary.
    /// - Sets the `fundedAt` field of the funded payments to the current block timestamp.
    function _fundN(uint256 n) internal returns (uint256) {
        uint256 start = currentFundingIndex();
        uint256 totalPayments_ = totalPayments();
        uint256 end = Math.min(start + n, totalPayments_);

        LoanStorage storage $ = getTinteroLoanStorage();
        $.currentFundingIndex = end.toUint24();

        uint256 totalPrincipal = 0;
        uint48 fundedAt = Time.timestamp();
        for (uint256 i = start; i < end; i++) {
            $.payments[i].fundedAt = fundedAt;
            totalPrincipal += $.payments[i].principal;
        }
        emit PaymentsFunded(start, end);

        return totalPrincipal;
    }

    /// @dev Withdraws the collateral to the beneficiary.
    ///
    /// Requirements:
    ///
    /// - Each payment collateral MUST be owned by this contract.
    ///
    /// Effects:
    ///
    /// - Moves to CANCELED state.
    /// - The payment collateral is transferred to the beneficiary.
    /// - Emits a `PaymentsWithdrawn` event.
    function _withdrawPaymentCollateral(
        LoanState state_,
        uint256 start,
        uint256 end
    ) internal {
        // Cancels the loan so it can't be funded anymore.
        if (state_ == LoanState.CREATED)
            getTinteroLoanStorage()._canceled = true;

        // Interactions
        _debitCollateral(start, end, beneficiary(), 0);
        emit PaymentsWithdrawn(start, end);
    }

    /// @dev Repays the current loan and `n` future payments.
    ///
    /// Requirements:
    ///
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
    /// - Emits a `PaymentsRepaid` event with the range of repaid payments.
    function _repay(
        uint256 start,
        uint256 end,
        address collateralReceiver
    ) internal {
        LoanStorage storage $ = getTinteroLoanStorage();
        uint256 principalPaid = _repayByTranches(start, end);
        $.currentPaymentIndex = end.toUint24();
        _debitCollateral(start, end, collateralReceiver, principalPaid);
    }

    /// @dev Repossess the collateral from payments.
    ///
    /// Requirements:
    ///
    /// - The collateral MUST be owned by this contract.
    /// - The receiver MUST implement IERC721Receiver to receive the collateral.
    ///
    /// Effects:
    ///
    /// - Moves to REPOSSESSED state.
    /// - The collateral is transferred to the receiver.
    /// - Emits a `PaymentsRepossessed` event with the range of repossessed payments.
    function _repossess(
        LoanState state_,
        uint256 start,
        uint256 end,
        address receiver
    ) internal {
        // Repossess so it can't be paid anymore.
        if (state_ == LoanState.DEFAULTED)
            getTinteroLoanStorage()._repossessed = true;

        uint256 principalRepossessed = 0;

        for (uint256 i = start; i < end; i++) {
            principalRepossessed += payment(i).principal;
        }
        emit PaymentsRepossessed(receiver, start, end);

        _debitCollateral(start, end, receiver, principalRepossessed);
    }

    /// @dev Upgrades the loan to a new implementation. Useful for renegotiating terms.
    function upgradeLoan(
        address newImplementation,
        bytes calldata data
    ) external {
        upgradeToAndCall(newImplementation, data);
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyLiquidityProvider {}

    /*************************/
    /*** Private Functions ***/
    /*************************/

    /// @dev Check that the current state of the loan matches the requirements described
    /// by the `allowedStates` bitmap. Otherwise, reverts with an UnexpectedLoanState error.
    /// This bitmap should be built using `_encodeStateBitmap`.
    function _validateStateBitmap(
        bytes32 allowedStates
    ) private view returns (LoanState currentState) {
        currentState = state();
        if (_encodeStateBitmap(currentState) & allowedStates == bytes32(0))
            revert UnexpectedLoanState(currentState, allowedStates);
    }

    /// @dev Encodes a `LoanState` into a `bytes32` representation where each bit enabled corresponds to
    /// the underlying position in the `LoanState` enum. For example:
    ///
    /// 0x000...10000
    ///   ^^^^^^----- ...
    ///         ^---- ONGOING
    ///          ^--- DEFAULTED
    ///           ^-- REPOSSESSED
    ///            ^- PAID
    function _encodeStateBitmap(
        LoanState loanState
    ) private pure returns (bytes32) {
        return bytes32(1 << uint8(loanState));
    }

    /// @dev Repays the payments from `start` to `end` by doing a single transfer per tranche.
    /// Assumes end is not greater than the total number of payments.
    ///
    /// Requirements:
    ///
    /// - The sender MUST have enough funds to repay the principal of the specified payments
    /// - The sender MUST have approved this contract to transfer the principal amount
    ///
    /// Effects:
    ///
    /// - The principal of the repaid payments is transferred from the sender to the receiver of each payment tranche
    /// - Moves to ONGOING if paid until below the default threshold.
    /// - Moves to PAID state if all payments are repaid.
    /// - Emits a `PaymentsRepaid` event with the range of repaid payments.
    function _repayByTranches(
        uint256 start,
        uint256 end
    ) private returns (uint256 principalPaid) {
        uint256 trancheIndex_ = currentTrancheIndex();

        uint96 _start;
        uint96 tEnd; // i.e. trancheEnd
        address _receiver;

        for (
            (_start, (tEnd, _receiver)) = (
                start.toUint96(),
                tranche(trancheIndex_)
            );
            _start < end;
            (_start, (tEnd, _receiver)) = (tEnd, tranche(trancheIndex_++))
        ) {
            (uint256 toPay, uint256 principalPaidInPayment) = _prepareToPay(
                _start,
                Math.min(tEnd, end)
            );
            principalPaid += principalPaidInPayment;
            // We tie funding to `msg.sender`, otherwise it enables arbitrary account draining if they approved the contract.
            lendingAsset().safeTransferFrom(msg.sender, _receiver, toPay);
            if (tEnd >= end) break;
        }
    }

    /// @dev Prepares the loan for repayment of `n` payments. Returns the total amount to pay.
    /// Assumes end is not greater than the total number of payments.
    ///
    /// Effects:
    ///
    /// - Moves to ONGOING if paid until below the default threshold.
    /// - Moves to PAID state if all payments are repaid.
    /// - Emits a `PaymentsRepaid` event with the range of repaid payments.
    function _prepareToPay(
        uint256 start,
        uint256 end
    ) private returns (uint256 toPay, uint256 principalPaid) {
        for (uint256 i = start; i < end; i++) {
            PaymentLib.Payment memory payment_ = payment(i);
            uint48 timepoint = Time.timestamp();
            principalPaid += payment_.principal;
            toPay += payment_.principal + payment_.accruedInterest(timepoint);
        }
        emit PaymentsRepaid(start, end);
    }

    /// @dev Disposes the collateral from payments. Burns the collateral if `collateralReceiver` is the zero address.
    ///
    /// Requirements:
    ///
    /// - Each payment collateral MUST be owned by this contract.
    ///
    /// Effects:
    ///
    /// - The collateral is transferred to the collateralReceiver if provided, otherwise it is burned.
    function _debitCollateral(
        uint256 start,
        uint256 end,
        address collateralReceiver,
        uint256 discountedPrincipal
    ) private {
        liquidityProvider().onDebit(discountedPrincipal);
        for (uint256 i = start; i < end; i++) {
            if (collateralReceiver == address(0))
                collateralAsset().burn(collateralId(i));
            else
                collateralAsset().safeTransferFrom(
                    address(this),
                    collateralReceiver,
                    collateralId(i)
                );

            // No need to update heldTokenIds since they can't be transferred back anymore
        }
    }
}

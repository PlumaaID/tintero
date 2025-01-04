// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {ITinteroLoan} from "./interfaces/ITinteroLoan.sol";
import {TinteroLoanView} from "./TinteroLoan.view.sol";
import {TinteroLoanStorage} from "./TinteroLoan.storage.sol";
import {LoanState} from "./interfaces/ITinteroLoan.types.sol";

contract TinteroLoan is
    Initializable,
    UUPSUpgradeable,
    AccessManagedUpgradeable,
    TinteroLoanView
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using PaymentLib for PaymentLib.Payment;
    using Checkpoints for Checkpoints.Trace160;
    using SafeCast for uint256;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @dev Initializes the loan with the provided parameters.
    ///
    /// @param authority_ The access manager for the loan. Can upgrade.
    /// @param liquidityProvider_ The address funding the loan.
    /// @param collateralAsset_ The ERC721 token used as collateral.
    /// @param beneficiary_ The address to receive the principal once funded.
    /// @param defaultThreshold_ The number of missed payments at which the loan defaults.
    /// @param payments_ The list of payments to be added to the loan.
    /// @param collateralTokenIds_ The list of collateral tokenIds to be added to the loan.
    ///
    /// Requirements:
    ///
    /// - The beneficiary MUST NOT be the liquidity provider or the zero address.
    ///
    /// See `_validatePushPaymentsAndCollectCollateral` for more details on the requirements.
    function initialize(
        address authority_,
        address liquidityProvider_,
        address collateralAsset_,
        address beneficiary_,
        uint16 defaultThreshold_,
        PaymentLib.Payment[] calldata payments_,
        uint256[] calldata collateralTokenIds_
    ) public initializer {
        __AccessManaged_init(authority_);
        LoanStorage storage $ = getTinteroLoanStorage();
        if (beneficiary_ == address(0) || beneficiary_ == liquidityProvider_)
            revert InvalidBeneficiary();
        $.liquidityProvider = IERC4626(liquidityProvider_);
        $.collateralAsset = ERC721Burnable(collateralAsset_);
        $.beneficiary = beneficiary_;
        $.defaultThreshold = defaultThreshold_;
        _validatePushPaymentsAndCollectCollateral(
            collateralTokenIds_,
            payments_
        );
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
    /// - Emits a `CreatedPayment` event for each payment added.
    function pushPayments(
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payment_
    ) external {
        if (msg.sender != liquidityProvider()) revert OnlyLiquidityProvider();
        _validateStateBitmap(_encodeStateBitmap(LoanState.CREATED));
        _validatePushPaymentsAndCollectCollateral(collateralTokenIds, payment_);
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
    function pushTranches(
        uint96[] calldata paymentIndexes,
        address[] calldata recipients
    ) external {
        if (msg.sender != liquidityProvider()) revert OnlyLiquidityProvider();
        _validateStateBitmap(_encodeStateBitmap(LoanState.CREATED));
        _validateAndPushTranches(paymentIndexes, recipients);
    }

    /// @dev Funds `n` payments from the loan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED or FUNDING state.
    /// - There MUST be at least 1 tranche defined.
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
    function fundN(uint256 n) external returns (uint256) {
        // Checks
        if (totalTranches() <= 0) revert EmptyTranches();
        _validateStateBitmap(
            _encodeStateBitmap(LoanState.CREATED) |
                _encodeStateBitmap(LoanState.FUNDING)
        );
        if (n == 0) return 0;

        // Effects
        uint256 totalPrincipal = _fundN(n);

        // Interactions
        lendingAsset().safeTransferFrom(
            liquidityProvider(),
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
    /// - Emits a `WithdrawnPayment` event for each payment withdrawn.
    function withdrawPaymentCollateral(uint256 start, uint256 end) external {
        // Checks
        if (msg.sender != beneficiary()) revert OnlyBeneficiary();
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
    /// - The loan MUST be in FUNDED or DEFAULTED state.
    /// - The sender MUST have enough funds to repay the principal of the specified payments
    /// - The sender MUST have approved this contract to transfer the principal amount
    ///
    /// Effects:
    ///
    /// - Moves to FUNDED if paid until below the default threshold.
    /// - Moves to PAID state if all payments are repaid.
    /// - The `currentPaymentIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the repaid payments is transferred from the sender to the receiver of each payment tranche
    /// - The collateral is transferred to the collateralReceiver if provided, otherwise it is burned.
    /// - Emits a `RepaidPayment` event for each payment repaid.
    function repayN(uint256 n, address collateralReceiver) public {
        // Checks
        _validateStateBitmap(
            _encodeStateBitmap(LoanState.FUNDED) |
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
    ///
    /// Effects:
    ///
    /// - Moves to REPOSSESSED state.
    /// - The collateral is transferred back to the liquidity provider.
    /// - Emits a `RepossessedPayment` event for each payment repossessed.
    function repossess(uint256 start, uint256 end) external {
        // Checks
        if (msg.sender != liquidityProvider()) revert OnlyLiquidityProvider();
        LoanState state_ = _validateStateBitmap(
            _encodeStateBitmap(LoanState.DEFAULTED) |
                _encodeStateBitmap(LoanState.REPOSSESSED)
        );

        // Effects and Interactions
        _repossess(state_, start, end);
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
    function _validatePushPaymentsAndCollectCollateral(
        uint256[] calldata collateralTokenIds_,
        PaymentLib.Payment[] calldata payments_
    ) internal {
        uint256 paymentsLength = payments_.length;
        // Checks
        if (collateralTokenIds_.length != paymentsLength)
            revert MismatchedPaymentCollateralIds();

        (, PaymentLib.Payment memory latest) = payment(totalPayments() - 1);

        uint256 totalPayments_ = totalPayments();
        uint256 latestMaturity = latest.maturedAt();

        // Checks and Effects
        for (uint256 i = 0; i < paymentsLength; i++)
            latestMaturity = _validatePushPayment(
                totalPayments_ + i,
                latestMaturity,
                collateralTokenIds_[i],
                payments_[i]
            );

        // Interactions
        ERC721Burnable asset = collateralAsset();
        for (uint256 i = 0; i < payments_.length; i++)
            _collectCollateral(asset, collateralTokenIds_[i]);
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
        uint96 lastIndex = 1; // Avoids 0 index so that the first tranche is always valid
        for (uint256 i = 0; i < paymentIndexesLength; i++) {
            uint96 paymentIndex = paymentIndexes_[i];
            if (paymentIndex <= lastIndex)
                revert UnincreasingTranchePaymentIndex();
            $._tranches.push(paymentIndex, uint160(recipients_[i]));
            emit CreatedTranche(
                totalTranches_ + i,
                paymentIndex,
                recipients_[i]
            );
        }

        if (totalTranches() >= totalPayments()) revert TooManyTranches();
    }

    /// @dev Validates the payment and adds it to the loan.
    ///
    /// Requirements:
    ///
    /// - The payment maturity date MUST NOT be before the latest maturity.
    /// - The payment MUST NOT have matured.
    /// - The collateral tokenId MUST not have been added before.
    /// - Emits a `CreatedPayment` event.
    function _validatePushPayment(
        uint256 i,
        uint256 latestMaturity,
        uint256 collateralTokenId,
        PaymentLib.Payment calldata payment_
    ) internal returns (uint256) {
        // Checks
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
        emit CreatedPayment(i, collateralTokenId, payment_);
        return maturedAt;
    }

    /// @dev Checks if the tokenId is owned by this contract and transfers it to this contract otherwise.
    ///
    /// Requirements:
    ///
    /// - The collateralTokenIds MUST exist.
    /// - The owner of each collateral tokenId MUST have approved this contract
    ///   to transfer it (if not the contract itself).
    function _collectCollateral(
        ERC721Burnable asset,
        uint256 tokenId
    ) internal {
        // Reverts if tokenId doesn't exist
        address assetOwner = asset.ownerOf(tokenId);
        if (assetOwner != address(this)) {
            // Reverts if the transfer fails
            // Unintentionally not using `safeTransferFrom` given the recipient is this contract.
            asset.transferFrom(assetOwner, address(this), tokenId);
        }
    }

    /// @dev Funds `n` payments from the loan. Returns the total principal to fund.
    /// The `end` index is capped to the total number of payments.
    ///
    /// Effects:
    ///
    /// - Moves to FUNDING state
    /// - Moves to FUNDED state if all payments are funded.
    /// - The `currentFundingIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the funded payments is transferred from the liquidity provider to the beneficiary.
    function _fundN(uint256 n) internal returns (uint256) {
        uint256 start = currentFundingIndex();
        uint256 totalPayments_ = totalPayments();
        uint256 end = Math.min(start + n, totalPayments_);

        LoanStorage storage $ = getTinteroLoanStorage();
        $.currentFundingIndex = end.toUint16();

        uint256 totalPrincipal = 0;
        for (uint256 i = start; i < end; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment_
            ) = payment(i);
            totalPrincipal += payment_.principal;
            emit FundedPayment(i, collateralTokenId, payment_.principal);
        }

        return totalPrincipal;
    }

    /// @dev Withdraws the collateral to the beneficiary.
    ///
    /// Effects:
    ///
    /// - Moves to CANCELED state.
    /// - The payment collateral is transferred to the beneficiary.
    /// - Emits a `WithdrawnPayment` event.
    function _withdrawPaymentCollateral(
        LoanState state_,
        uint256 start,
        uint256 end
    ) internal {
        // Cancels the loan so it can't be funded anymore.
        if (state_ == LoanState.CREATED)
            getTinteroLoanStorage()._canceled = true;

        // Interactions
        for (uint256 i = start; i < end; i++) {
            (uint256 tokenId, PaymentLib.Payment memory payment_) = payment(i);
            _transferCollateral(tokenId, beneficiary(), payment_.principal);
            emit WithdrawnPayment(i, tokenId, payment_.principal);
        }
    }

    /// @dev Prepares the loan for repayment of `n` payments. Returns the total amount to pay.
    ///
    /// Effects:
    ///
    /// - Moves to FUNDED if paid until below the default threshold.
    /// - Moves to PAID state if all payments are repaid.
    /// - Emits a `RepaidPayment` event for each payment repaid.
    function _prepareToPay(
        uint256 start,
        uint256 end
    ) internal returns (uint256) {
        uint256 toPay = 0;
        for (uint256 i = start; i < end; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment_
            ) = payment(i);
            uint48 timepoint = Time.timestamp();
            toPay += payment_.principal + payment_.accruedInterest(timepoint);
            emit RepaidPayment(
                i,
                collateralTokenId,
                payment_.principal,
                payment_.regularAccruedInterest(timepoint),
                payment_.premiumAccruedInterest(timepoint)
            );
        }

        return toPay;
    }

    /// @dev Repays the current loan and `n` future payments.
    ///
    /// Requirements:
    ///
    /// - The sender MUST have enough funds to repay the principal of the specified payments
    /// - The sender MUST have approved this contract to transfer the principal amount
    ///
    /// Effects:
    ///
    /// - The `currentPaymentIndex` is incremented by `n` or the remaining payments.
    /// - The principal of the repaid payments is transferred from the sender to the receiver of each payment tranche
    /// - The collateral is transferred to the collateralReceiver if provided, otherwise it is burned.
    function _repay(
        uint256 start,
        uint256 end,
        address collateralReceiver
    ) internal {
        LoanStorage storage $ = getTinteroLoanStorage();
        $.currentPaymentIndex = end.toUint16();
        _repayByTranches(start, end);
        _disposeCollateral(start, end, collateralReceiver);
    }

    /// @dev Repossess the collateral from payments.
    ///
    /// Requirements:
    ///
    /// - The collateral MUST be owned by this contract.
    ///
    /// Effects:
    ///
    /// - Moves to REPOSSESSED state.
    /// - The collateral is transferred back to the liquidity provider.
    /// - Emits a `RepossessedPayment` event for each payment repossessed.
    function _repossess(LoanState state_, uint256 start, uint256 end) internal {
        // Repossess so it can't be paid anymore.
        if (state_ == LoanState.DEFAULTED)
            getTinteroLoanStorage()._repossessed = true;

        for (uint256 i = start; i < end; i++) {
            (uint256 tokenId, PaymentLib.Payment memory payment_) = payment(i);
            _transferCollateral(
                tokenId,
                liquidityProvider(),
                payment_.principal
            );
            // No need to update heldTokenIds since they can't be transferred back anymore
            emit RepossessedPayment(i, tokenId, payment_.principal);
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}

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
    ///         ^---- FUNDED
    ///          ^--- DEFAULTED
    ///           ^-- REPOSSESSED
    ///            ^- PAID
    function _encodeStateBitmap(
        LoanState loanState
    ) private pure returns (bytes32) {
        return bytes32(1 << uint8(loanState));
    }

    /// @dev Repays the payments from `start` to `end` by doing a single transfer per tranche.
    ///
    /// Requirements:
    ///
    /// - The sender MUST have enough funds to repay the principal of the specified payments
    /// - The sender MUST have approved this contract to transfer the principal amount
    ///
    /// Effects:
    ///
    /// - The principal of the repaid payments is transferred from the sender to the receiver of each payment tranche
    function _repayByTranches(uint256 start, uint256 end) private {
        uint256 trancheIndex_ = currentTrancheIndex();
        (uint96 tranchePaymentIndex_, address trancheReceiver_) = tranche(
            trancheIndex_
        );

        assert(tranchePaymentIndex_ >= start);

        uint256 totalTranches_ = totalTranches();
        uint96 nextTranchePaymentIndex_;
        address nextTrancheReceiver_;

        while (start < end) {
            assert(tranchePaymentIndex_ < totalTranches_);
            (nextTranchePaymentIndex_, nextTrancheReceiver_) = tranche(
                ++trancheIndex_ // Next tranche
            );
            lendingAsset().safeTransferFrom(
                msg.sender,
                trancheReceiver_,
                _prepareToPay(start, nextTranchePaymentIndex_)
            );
            start = nextTranchePaymentIndex_;
            trancheReceiver_ = nextTrancheReceiver_;
        }
    }

    /// @dev Disposes the collateral from payments. Burns the collateral if `collateralReceiver` is the zero address.
    ///
    /// Effects:
    ///
    /// - The collateral is transferred to the collateralReceiver if provided, otherwise it is burned.
    function _disposeCollateral(
        uint256 start,
        uint256 end,
        address collateralReceiver
    ) private {
        for (uint256 i = start; i < end; i++) {
            (uint256 tokenId, PaymentLib.Payment memory payment_) = payment(i);
            if (collateralReceiver == address(0))
                collateralAsset().burn(tokenId);
            else
                _transferCollateral(
                    tokenId,
                    collateralReceiver,
                    payment_.principal
                );

            // No need to update heldTokenIds since they can't be transferred back anymore
        }
    }

    /// @dev Transfer the collateral tokenId to the recipient and
    /// includes the encoded principal as data.
    function _transferCollateral(
        uint256 tokenId,
        address to,
        uint256 principal
    ) private {
        collateralAsset().safeTransferFrom(
            address(this),
            to,
            tokenId,
            abi.encode(principal)
        );
    }
}

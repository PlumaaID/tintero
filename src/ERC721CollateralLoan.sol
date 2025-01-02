// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {IERC721CollateralLoan} from "./interfaces/IERC721CollateralLoan.sol";

contract ERC721CollateralLoan is
    Initializable,
    UUPSUpgradeable,
    AccessManagedUpgradeable,
    IERC721CollateralLoan
{
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.UintSet;
    using PaymentLib for PaymentLib.Payment;

    // keccak256(abi.encode(uint256(keccak256("PlumaaID.storage.ERC721CollateralLoan")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC721_COLLATERAl_LOAN_STORAGE =
        0xd3b6f225e977966761f1657a7744205f224d1c596f9144ffc3e50665071a9800;

    struct LoanStorage {
        IERC4626 liquidityProvider;
        IERC721 collateralAsset;
        PaymentLib.Payment[] payments;
        uint256[] collateralTokenIds;
        EnumerableSet.UintSet heldTokenIds;
        address beneficiary;
        uint16 defaultThreshold; // Up to 65535 payments
        uint16 currentPaymentIndex; // Up to 65535 payments
        uint16 currentFundingIndex; // Up to 65535 payments
        bool _funded;
        bool _canceled;
        bool _repossessed;
        bool _paid;
    }

    constructor() {
        _disableInitializers();
    }

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
        LoanStorage storage $ = getERC721CollateralLoanStorage();
        if (beneficiary_ == address(0)) revert ZeroAddress();
        $.liquidityProvider = IERC4626(liquidityProvider_);
        $.collateralAsset = IERC721(collateralAsset_);
        $.beneficiary = beneficiary_;
        $.defaultThreshold = defaultThreshold_;
        _validatePaymentsAndCollectCollateral(collateralTokenIds_, payments_);
    }

    /**********************/
    /*** View Functions ***/
    /**********************/

    /// @dev Address of the ERC20 token lent.
    function lendingAsset() public view returns (IERC20) {
        return IERC20(IERC4626(liquidityProvider()).asset());
    }

    /// @dev Address of the ERC721 token used as collateral.
    function collateralAsset() public view returns (IERC721) {
        return getERC721CollateralLoanStorage().collateralAsset;
    }

    /// @dev Funder's address.
    function liquidityProvider() public view returns (address) {
        return address(getERC721CollateralLoanStorage().liquidityProvider);
    }

    /// @dev Get payment details.
    function payment(
        uint256 index
    )
        public
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory)
    {
        LoanStorage storage $ = getERC721CollateralLoanStorage();
        return ($.collateralTokenIds[index], $.payments[index]);
    }

    /// @dev Get the index of the current payment yet to be repaid.
    function currentPaymentIndex() public view returns (uint256) {
        return getERC721CollateralLoanStorage().currentPaymentIndex;
    }

    /// @dev Get the index of the current payment yet to be funded.
    function currentFundingIndex() public view returns (uint256) {
        return getERC721CollateralLoanStorage().currentFundingIndex;
    }

    /// @dev Get the payment at which the loan is currently at and the
    /// outstanding amount until the next payment.
    function currentPayment()
        public
        view
        returns (uint256 collateralTokenId, PaymentLib.Payment memory)
    {
        return payment(currentPaymentIndex());
    }

    /// @dev Get the total number of payments.
    function totalPayments() public view returns (uint256) {
        return getERC721CollateralLoanStorage().payments.length;
    }

    /// @dev Address of the beneficiary of the loan.
    function beneficiary() public view returns (address) {
        return getERC721CollateralLoanStorage().beneficiary;
    }

    /// @dev Amount of missed payments at which the loan is defaulted.
    function defaultThreshold() public view returns (uint256) {
        return getERC721CollateralLoanStorage().defaultThreshold;
    }

    /// @dev The state of the loan.
    function state() public view returns (LoanState) {
        LoanStorage storage $ = getERC721CollateralLoanStorage();

        if ($._repossessed) return LoanState.REPOSSESSED;
        if ($._paid) return LoanState.PAID;
        if ($._canceled) return LoanState.CANCELED;

        uint256 start = currentPaymentIndex();
        uint256 threshold = defaultThreshold();

        // If any of the following payments until the threshold is not matured, the loan is not defaulted
        for (uint256 i = start; i < start + threshold; i++) {
            (, PaymentLib.Payment memory payment_) = payment(i);
            if (!payment_.matured()) return LoanState.DEFAULTED;
        }

        if ($._funded) return LoanState.FUNDED;
        return LoanState.CREATED;
    }

    /**************************/
    /*** External Functions ***/
    /**************************/

    /// @dev Adds a payment to the loan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED state.
    /// - Those of _validatePaymentsAndCollectCollateral
    /// - The caller MUST be the liquidity provider.
    function pushPayments(
        uint256[] calldata collateralTokenIds,
        PaymentLib.Payment[] calldata payment_
    ) external {
        if (msg.sender != liquidityProvider()) revert OnlyLiquidityProvider();
        _validateStateBitmap(_encodeStateBitmap(LoanState.CREATED));
        _validatePaymentsAndCollectCollateral(collateralTokenIds, payment_);
    }

    /// @dev Funds `n` payments from the loan loan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED state.
    /// - The liquidityProvider MUST have enough funds to repay the principal of the current payment
    /// - This contract mus have been approved to transfer the principal
    ///   amount from the liquidity provider.
    function fundN(uint256 n) external returns (uint256) {
        // Checks
        _validateStateBitmap(_encodeStateBitmap(LoanState.CREATED));
        if (n == 0) return 0;

        // Effects
        uint256 start = currentFundingIndex();
        uint256 totalPayments_ = totalPayments();
        uint256 end = Math.min(start + n, totalPayments_);

        LoanStorage storage $ = getERC721CollateralLoanStorage();
        $.currentFundingIndex = SafeCast.toUint16(end);
        if (end == totalPayments_) $._funded = true;

        uint256 totalPrincipal = 0;
        for (uint256 i = start; i < end; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment_
            ) = payment(i);
            totalPrincipal += payment_.principal;
            emit FundedPayment(i, collateralTokenId, payment_.principal);
        }

        // Interactions
        lendingAsset().safeTransferFrom(
            liquidityProvider(),
            beneficiary(),
            totalPrincipal
        );

        return totalPrincipal;
    }

    /// @dev Withdraws the collateral to the beneficiary. Cancels the loan.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in CREATED or CANCELED state.
    /// - Each payment collateral MUST be owned by this contract.
    /// - The caller MUST be the beneficiary.
    function withdrawPaymentCollateral(uint256 start, uint256 end) external {
        if (msg.sender != beneficiary()) revert OnlyBeneficiary();

        _validateStateBitmap(
            _encodeStateBitmap(LoanState.CANCELED) |
                _encodeStateBitmap(LoanState.CREATED)
        );

        // Cancels the loan so it can't be funded anymore.
        if (state() == LoanState.CREATED)
            getERC721CollateralLoanStorage()._canceled = true;

        for (uint256 i = start; i < end; i++) {
            (uint256 tokenId, PaymentLib.Payment memory payment_) = payment(i);
            collateralAsset().safeTransferFrom(
                address(this),
                beneficiary(),
                tokenId
            );
            emit WithdrawnPayment(i, tokenId, payment_.principal);
        }
    }

    /// @dev Repays the current loan payment. Same requirements as `repayN`.
    function repayCurrent() external {
        repayN(0);
    }

    /// @dev Repays the current loan and `n` future payments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in FUNDED or DEFAULTED state.
    /// - The beneficiary MUST have enough funds to repay the principal of the current payment
    /// - The beneficiary MUST have approved this contract to transfer the principal amount
    function repayN(uint256 n) public {
        _validateStateBitmap(
            _encodeStateBitmap(LoanState.FUNDED) |
                _encodeStateBitmap(LoanState.DEFAULTED)
        );

        uint256 start = currentPaymentIndex();
        uint256 totalPayments_ = totalPayments();
        uint256 end = Math.min(start + 1 + n, totalPayments_);

        LoanStorage storage $ = getERC721CollateralLoanStorage();
        $.currentPaymentIndex = SafeCast.toUint16(end);

        // Marks the loan as paid so no other interaction can be done.
        if (end == totalPayments_)
            getERC721CollateralLoanStorage()._paid = true;

        uint256 totalPrincipal = 0;
        for (uint256 i = start; i < end; i++) {
            (
                uint256 collateralTokenId,
                PaymentLib.Payment memory payment_
            ) = payment(i);
            uint48 timepoint = Time.timestamp();
            totalPrincipal +=
                payment_.principal +
                payment_.accruedInterest(timepoint);
            emit RepaidPayment(
                i,
                collateralTokenId,
                payment_.principal,
                payment_.regularAccruedInterest(timepoint),
                payment_.premiumAccruedInterest(timepoint)
            );
        }

        lendingAsset().safeTransferFrom(
            beneficiary(),
            liquidityProvider(),
            totalPrincipal
        );
    }

    /// @dev Repossess the collateral from payments.
    ///
    /// Requirements:
    ///
    /// - The loan MUST be in DEFAULTED or REPOSSESSED state.
    /// - The caller MUST be the liquidity provider.
    function repossess(uint256 start, uint256 end) external {
        if (msg.sender != liquidityProvider()) revert OnlyLiquidityProvider();

        _validateStateBitmap(
            _encodeStateBitmap(LoanState.DEFAULTED) |
                _encodeStateBitmap(LoanState.REPOSSESSED)
        );

        // Cancels so it can't be paid anymore.
        if (state() == LoanState.DEFAULTED)
            getERC721CollateralLoanStorage()._repossessed = true;

        for (uint256 i = start; i < end; i++) {
            (uint256 tokenId, PaymentLib.Payment memory payment_) = payment(i);
            collateralAsset().safeTransferFrom(
                address(this),
                liquidityProvider(),
                tokenId
            );
            // No need to update heldTokenIds since they can't be transferred back anymore
            emit RepossessedPayment(i, tokenId, payment_.principal);
        }
    }

    /**************************/
    /*** Internal Functions ***/
    /**************************/

    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}

    /// @dev Performs validations on the payments to be added to the loan.
    ///
    /// Requirements:
    ///
    /// - The collateral token IDs and payments arrays MUST have the same length.
    /// - The payments MUST be ordered by maturity date.
    /// - The payments MUST NOT have matured.
    /// - The collateral tokenIds MUST be unique.
    /// - The collateralTokenIds MUST exist.
    /// - The owner of each collateral tokenId MUST have approved this contract
    ///   to transfer it (if not the contract itself).
    function _validatePaymentsAndCollectCollateral(
        uint256[] calldata collateralTokenIds_,
        PaymentLib.Payment[] calldata payments_
    ) internal {
        // Checks
        if (collateralTokenIds_.length != payments_.length)
            revert MismatchedPaymentCollateralIds();

        LoanStorage storage $ = getERC721CollateralLoanStorage();
        (, PaymentLib.Payment memory latest) = payment(totalPayments() - 1);
        uint256 latestMaturity = latest.maturedAt();

        for (uint256 i = 0; i < payments_.length; i++) {
            uint256 tokenId = collateralTokenIds_[i];
            PaymentLib.Payment calldata payment_ = payments_[i];

            if (payment_.maturedAt() < latestMaturity)
                revert UnorderedPayments();

            if (
                payment_.matured() /* || payment_.defaulted() */ // Default is strictly higher or equal to maturity
            ) revert PaymentMatured(tokenId);

            if ($.heldTokenIds.contains(tokenId))
                // Technically an effect, put at last intentionally
                revert DuplicatedCollateral(tokenId);

            latestMaturity = payment_.maturedAt();
        }

        // Effects

        // Interactions
        IERC721 asset = collateralAsset();
        for (uint256 i = 0; i < payments_.length; i++) {
            uint256 tokenId = collateralTokenIds_[i];
            // Reverts if tokenId doesn't exist
            address assetOwner = asset.ownerOf(tokenId);
            if (assetOwner != address(this)) {
                // Reverts if the transfer fails
                // Unintentionally not using `safeTransferFrom` given the recipient is this contract.
                asset.transferFrom(assetOwner, address(this), tokenId);
            }
        }
    }

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
    ///         ^---- CREATED
    ///          ^--- CANCELED
    ///           ^-- FUNDED
    ///            ^- DEFAULTED
    function _encodeStateBitmap(
        LoanState loanState
    ) private pure returns (bytes32) {
        return bytes32(1 << uint8(loanState));
    }

    /// @notice Get EIP-7201 storage
    function getERC721CollateralLoanStorage()
        private
        pure
        returns (LoanStorage storage $)
    {
        assembly ("memory-safe") {
            $.slot := ERC721_COLLATERAl_LOAN_STORAGE
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {TinteroLoanStorage} from "./TinteroLoan.storage.sol";
import {LoanState} from "./interfaces/ITinteroLoan.types.sol";
import {ITinteroVault} from "./interfaces/ITinteroVault.sol";

abstract contract TinteroLoanView is TinteroLoanStorage {
    using PaymentLib for PaymentLib.Payment;
    using Checkpoints for Checkpoints.Trace160;
    using SafeCast for uint256;

    /// @dev Address of the ERC20 token lent.
    function lendingAsset() public view returns (IERC20) {
        return IERC20(IERC4626(address(liquidityProvider())).asset());
    }

    /// @dev Address of the ERC721 token used as collateral.
    function collateralAsset() public view returns (ERC721Burnable) {
        return ERC721Burnable(getTinteroLoanStorage().collateralAsset);
    }

    /// @dev Address of the liquidity provider funding the loan.
    function liquidityProvider() public view returns (ITinteroVault) {
        return ITinteroVault(getTinteroLoanStorage().liquidityProvider);
    }

    /// @dev Get the index at which the tranche starts and its recipient.
    /// A tranche is a collection of payments from [previousPaymentIndex ?? 0, paymentIndex).
    function tranche(
        uint256 trancheIndex
    ) public view returns (uint96 paymentIndex, address recipient) {
        Checkpoints.Checkpoint160 memory trace = getTinteroLoanStorage()
            ._tranches
            .at(trancheIndex.toUint32());
        return (trace._key, address(trace._value));
    }

    /// @dev Get the index of the current tranche.
    function currentTrancheIndex() public view returns (uint256) {
        return
            // Last (most recent) tranche for current payment index
            getTinteroLoanStorage()._tranches.upperLookup(
                currentPaymentIndex().toUint96()
            );
    }

    /// @dev Total tranches in the loan.
    function totalTranches() public view returns (uint256) {
        return getTinteroLoanStorage()._tranches.length();
    }

    /// @dev Get payment details. A Payment is a struct with a principal and interest terms.
    function payment(
        uint256 index
    ) public view returns (PaymentLib.Payment memory) {
        return getTinteroLoanStorage().payments[index];
    }

    /// @dev Get the collateral tokenId for a payment.
    function collateralId(uint256 index) public view returns (uint256) {
        return getTinteroLoanStorage().collateralTokenIds[index];
    }

    /// @dev Get the index of the current payment yet to be repaid.
    function currentPaymentIndex() public view returns (uint256) {
        return getTinteroLoanStorage().currentPaymentIndex;
    }

    /// @dev Get the total number of payments.
    function totalPayments() public view returns (uint256) {
        return getTinteroLoanStorage().payments.length;
    }

    /// @dev Get the index of the current payment yet to be funded.
    function currentFundingIndex() public view returns (uint256) {
        return getTinteroLoanStorage().currentFundingIndex;
    }

    /// @dev Address of the beneficiary of the loan.
    function beneficiary() public view returns (address) {
        return getTinteroLoanStorage().beneficiary;
    }

    /// @dev Amount of missed payments at which the loan is defaulted.
    function defaultThreshold() public view returns (uint256) {
        return getTinteroLoanStorage().defaultThreshold;
    }

    /// @dev Get the current state of the loan.
    function state() public view returns (LoanState) {
        uint256 fundingIndex = currentFundingIndex();
        LoanStorage storage $ = getTinteroLoanStorage();

        if ($._repossessed) return LoanState.REPOSSESSED;
        uint256 current = currentPaymentIndex();
        uint256 totalPaymentsCount = totalPayments();
        if (totalPaymentsCount == 0) return LoanState.CREATED; // No payments, no further state
        if (current == totalPaymentsCount) return LoanState.PAID;
        if ($._canceled) return LoanState.CANCELED;
        if (_defaulted(current)) return LoanState.DEFAULTED;
        if (fundingIndex != 0) {
            if (fundingIndex == totalPaymentsCount) return LoanState.ONGOING;
            return LoanState.FUNDING;
        }
        return LoanState.CREATED;
    }

    function _defaulted(uint256 current) internal view returns (bool) {
        uint256 threshold = defaultThreshold();
        uint256 defaultAt = current + threshold;

        if (defaultAt > totalPayments()) return false; // Cannot default if there are no more payments

        // If any of the following payments until the threshold is not matured, the loan is not defaulted
        for (uint256 i = current; i < defaultAt; i++) {
            if (!payment(i).defaulted()) return false;
        }

        return true;
    }
}

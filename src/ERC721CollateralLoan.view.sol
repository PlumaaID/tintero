// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {ERC721CollateralLoanStorage} from "./ERC721CollateralLoan.storage.sol";
import {LoanState} from "./interfaces/IERC721CollateralLoan.types.sol";

abstract contract ERC721CollateralLoanView is ERC721CollateralLoanStorage {
    using PaymentLib for PaymentLib.Payment;

    /// @dev Address of the ERC20 token lent.
    function lendingAsset() public view returns (IERC20) {
        return IERC20(IERC4626(liquidityProvider()).asset());
    }

    /// @dev Address of the ERC721 token used as collateral.
    function collateralAsset() public view returns (ERC721Burnable) {
        return getERC721CollateralLoanStorage().collateralAsset;
    }

    /// @dev Address of the liquidity provider funding the loan.
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

    /// @dev Get the payment at which the loan is currently at and its collateral tokenId.
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

    /// @dev Get the current state of the loan.
    function state() public view returns (LoanState) {
        LoanStorage storage $ = getERC721CollateralLoanStorage();

        if ($._repossessed) return LoanState.REPOSSESSED;
        uint256 current = currentPaymentIndex();
        if (current == totalPayments()) return LoanState.PAID;
        if ($._canceled) return LoanState.CANCELED;

        uint256 threshold = defaultThreshold();
        uint256 defaultAfter = current + threshold;

        // If any of the following payments until the threshold is not matured, the loan is not defaulted
        uint256 last = defaultAfter - 1;
        for (uint256 i = current; i < defaultAfter; i++) {
            (, PaymentLib.Payment memory payment_) = payment(i);
            if (!payment_.matured()) break;
            if (i == last) return LoanState.DEFAULTED;
        }

        if (currentFundingIndex() == totalPayments()) return LoanState.FUNDED;
        return LoanState.CREATED;
    }
}

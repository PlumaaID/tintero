// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentLib} from "../utils/PaymentLib.sol";

interface ITinteroLoanEvents {
    /// @dev Emitted when a payment is created.
    event CreatedPayment(
        uint256 indexed index,
        uint256 indexed tokenId,
        PaymentLib.Payment payment
    );

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

    /// @dev Emitted when a loan payment is repossessed by the liquidity provider.
    event RepossessedPayment(
        uint256 indexed index,
        uint256 indexed tokenId,
        uint256 principal
    );
}

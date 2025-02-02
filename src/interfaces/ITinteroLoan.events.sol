// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PaymentLib} from "../utils/PaymentLib.sol";

interface ITinteroLoanEvents {
    /// @dev Emitted when a payment is created.
    event PaymentCreated(
        uint256 indexed index,
        uint256 indexed tokenId,
        PaymentLib.Payment payment
    );

    /// @dev Emitted when a tranche is created.
    event TrancheCreated(
        uint256 indexed index,
        uint256 indexed paymentIndex,
        address indexed receiver
    );

    /// @dev Emitted when a set of payments is funded. (startIndex, endIndex]
    event PaymentsFunded(uint256 indexed startIndex, uint256 indexed endIndex);

    /// @dev Emitted when the collateral is withdrawn from a set of payments. (startIndex, endIndex]
    event PaymentsWithdrawn(
        uint256 indexed startIndex,
        uint256 indexed endIndex
    );

    /// @dev Emitted when a set of payment is repaid. (startIndex, endIndex]
    event PaymentsRepaid(uint256 indexed startIndex, uint256 indexed endIndex);

    /// @dev Emitted when a set of payments are repossessed by the liquidity provider. (startIndex, endIndex]
    event PaymentsRepossessed(
        address indexed recipient,
        uint256 indexed startIndex,
        uint256 indexed endIndex
    );
}

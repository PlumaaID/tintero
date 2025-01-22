// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev Interface for a contract to receive debit callbacks.
interface IPaymentCallback {
    /// @dev Debits an outstanding principal from the implementing contract.
    function onDebit(uint256 principal) external;
}

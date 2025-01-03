// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @dev The possible states of a loan.
enum LoanState {
    CREATED,
    CANCELED,
    FUNDED,
    DEFAULTED,
    REPOSSESSED,
    PAID
}

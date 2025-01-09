// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {ITinteroLoan} from "./interfaces/ITinteroLoan.sol";

abstract contract TinteroLoanStorage is ITinteroLoan {
    // keccak256(abi.encode(uint256(keccak256("PlumaaID.storage.TinteroLoan")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant TINTERO_LOAN_STORAGE =
        0x1f389b2eba3c6a855b1e43cd4e972600e00166178892203933678c6474e96300;

    struct LoanStorage {
        address liquidityProvider;
        // Invariant: _tranches.length() <= payments.length - 1
        Checkpoints.Trace160 _tranches; // paymentIndex << 160 | recipient
        bool _canceled;
        bool _repossessed;
        // 94 bits gap
        address collateralAsset;
        // 96 bits gap
        PaymentLib.Payment[] payments;
        uint256[] collateralTokenIds;
        EnumerableSet.UintSet heldTokenIds;
        address beneficiary;
        uint24 defaultThreshold; // Up to 16,777,216 payments
        uint24 currentPaymentIndex; // Up to 16,777,216 payments
        uint24 currentFundingIndex; // Up to 16,777,216 payments
        // 24 bits gap
    }

    /// @notice Get EIP-7201 storage
    function getTinteroLoanStorage()
        internal
        pure
        returns (LoanStorage storage $)
    {
        assembly ("memory-safe") {
            $.slot := TINTERO_LOAN_STORAGE
        }
    }
}

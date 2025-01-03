// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {PaymentLib} from "./utils/PaymentLib.sol";
import {ITinteroLoan} from "./interfaces/ITinteroLoan.sol";

abstract contract TinteroLoanStorage is ITinteroLoan {
    // keccak256(abi.encode(uint256(keccak256("PlumaaID.storage.TinteroLoan")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC721_COLLATERAl_LOAN_STORAGE =
        0xd3b6f225e977966761f1657a7744205f224d1c596f9144ffc3e50665071a9800;

    struct LoanStorage {
        IERC4626 liquidityProvider;
        ERC721Burnable collateralAsset;
        PaymentLib.Payment[] payments;
        uint256[] collateralTokenIds;
        EnumerableSet.UintSet heldTokenIds;
        address beneficiary;
        uint16 defaultThreshold; // Up to 65535 payments
        uint16 currentPaymentIndex; // Up to 65535 payments
        uint16 currentFundingIndex; // Up to 65535 payments
        bool _canceled;
        bool _repossessed;
    }

    /// @notice Get EIP-7201 storage
    function getTinteroLoanStorage()
        internal
        pure
        returns (LoanStorage storage $)
    {
        assembly ("memory-safe") {
            $.slot := ERC721_COLLATERAl_LOAN_STORAGE
        }
    }
}

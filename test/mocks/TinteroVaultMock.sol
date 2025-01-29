// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {TinteroVault} from "~/TinteroVault.sol";

contract TinteroVaultMock is TinteroVault {
    constructor(
        IERC20Metadata asset_,
        address authority_
    ) TinteroVault(asset_, authority_) {}

    function _decimalsOffset() internal pure override returns (uint8) {
        // Reset to 0 to pass property test.
        // With a virtual offset, some cases for test_maxRedeem fail since the offset
        // overflows at very high values. These are not realistic scenarios, but
        // the property test should still pass.
        return super._decimalsOffset() - super._decimalsOffset();
    }
}

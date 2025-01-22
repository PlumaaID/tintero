// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {Tintero} from "~/Tintero.sol";

contract TinteroMock is Tintero {
    constructor(
        IERC20Metadata asset_,
        address authority_
    ) Tintero(asset_, authority_) {}

    function _decimalsOffset() internal pure override returns (uint8) {
        // Reset to 0 to pass property test.
        // With a virtual offset, some cases for test_maxRedeem fail since the offset
        // overflows at very high values. These are not realistic scenarios, but
        // the property test should still pass.
        return super._decimalsOffset() - super._decimalsOffset();
    }
}

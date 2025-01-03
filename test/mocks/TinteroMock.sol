// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {Tintero} from "~/Tintero.sol";

contract TinteroMock is Tintero {
    constructor(
        IERC20Metadata asset_,
        address authority_
    ) Tintero(asset_, authority_) {}
}

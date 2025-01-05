// SPDX-License-Identifier: MIT
// Vendored and modified from https://gist.github.com/saucepoint/00ae29ae70a38f787b1f1aca6ef23f1f
pragma solidity ^0.8.13;

// author: saucepoint
// run with a mainnet --fork-url such as:
//   forge test --fork-url https://rpc.ankr.com/eth

import "forge-std/Test.sol";

// temporary interface for minting USDC
// should be implemented more extensively, and organized somewhere
interface IUSDC {
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
    function mint(address to, uint256 amount) external;
    function configureMinter(
        address minter,
        uint256 minterAllowedAmount
    ) external;
    function masterMinter() external view returns (address);
}

contract USDCTest is Test {
    // USDC contract address on arbitrum
    IUSDC usdc = IUSDC(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);

    function setUp() public virtual {
        // spoof .configureMinter() call with the master minter account
        vm.prank(usdc.masterMinter());
        // allow this test contract to mint USDC
        usdc.configureMinter(address(this), type(uint256).max);

        // mint $1000 USDC to the test contract (or an external user)
        usdc.mint(address(this), 1000e6);
    }
}

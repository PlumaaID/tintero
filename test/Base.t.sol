// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Witnesser} from "~/Witnesser.sol";
import {Endorser} from "~/Endorser.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract BaseTest is Test {
    AccessManager internal accessManager;
    Witnesser internal witnesser;
    Endorser internal endorser;

    function setUp() public virtual {
        accessManager = new AccessManager(address(this));
        witnesser = Witnesser(
            Upgrades.deployUUPSProxy(
                "Witnesser.sol",
                abi.encodeCall(Witnesser.initialize, (address(accessManager)))
            )
        );
        endorser = Endorser(
            Upgrades.deployUUPSProxy(
                "Endorser.sol",
                abi.encodeCall(
                    Endorser.initialize,
                    (address(accessManager), address(witnesser))
                )
            )
        );
    }
}

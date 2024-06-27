// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Witness} from "~/Witness.sol";
import {Endorser} from "~/Endorser.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";

contract BaseTest is Test {
    AccessManager internal accessManager;
    Witness internal witness;
    Endorser internal endorser;

    uint64 internal constant relayerRole =
        uint64(bytes8(keccak256("PlumaaID.Relayer")));

    function setUp() public virtual {
        accessManager = new AccessManager(address(this));
        witness = Witness(
            Upgrades.deployUUPSProxy(
                "Witness.sol",
                abi.encodeCall(Witness.initialize, (address(accessManager)))
            )
        );
        endorser = Endorser(
            Upgrades.deployUUPSProxy(
                "Endorser.sol",
                abi.encodeCall(
                    Endorser.initialize,
                    (address(accessManager), address(witness))
                )
            )
        );
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Endorser} from "~/Endorser.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {EndorserMock} from "./mocks/EndorserMock.sol";

contract BaseTest is Test {
    AccessManager internal accessManager;
    EndorserMock internal endorser;

    uint64 internal constant PROVENANCE_AUTHORIZER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")));

    // From https://docs.witness.co/additional-notes/deployments
    IWitness constant WITNESS =
        IWitness(0x0000000e143f453f45B2E1cCaDc0f3CE21c2F06a);

    function setUp() public virtual {
        // Perform upgrade safetiness checks
        Upgrades.deployUUPSProxy(
            "Endorser.sol",
            abi.encodeCall(
                Endorser.initialize,
                (address(accessManager), WITNESS)
            )
        );

        accessManager = new AccessManager(address(this));
        endorser = EndorserMock(
            address(
                new ERC1967Proxy(
                    address(new EndorserMock()),
                    abi.encodeCall(
                        Endorser.initialize,
                        (address(accessManager), WITNESS)
                    )
                )
            )
        );
    }
}

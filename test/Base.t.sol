// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {Endorser} from "~/Endorser.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {EndorserMock} from "./mocks/EndorserMock.sol";
import {TinteroMock} from "./mocks/TinteroMock.sol";
import {USDCTest} from "./USDCTest.t.sol";

contract BaseTest is Test, USDCTest {
    AccessManager internal accessManager;
    EndorserMock internal endorser;
    TinteroMock internal tintero;

    uint64 internal constant PROVENANCE_AUTHORIZER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")));
    uint64 internal constant WITNESS_SETTER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.WITNESS_SETTER")));
    uint64 internal constant TINTERO_MANAGER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.TINTERO_MANAGER")));

    // From https://docs.witness.co/additional-notes/deployments
    IWitness constant WITNESS =
        IWitness(0x0000000e143f453f45B2E1cCaDc0f3CE21c2F06a);

    function setUp() public virtual override {
        super.setUp();

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

        tintero = new TinteroMock(
            IERC20Metadata(address(usdc)),
            address(accessManager)
        );
    }
}

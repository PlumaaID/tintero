// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Upgrades} from "@openzeppelin/foundry-upgrades/Upgrades.sol";
import {BaseScript} from "./utils/Base.s.sol";
import {Timestamper} from "~/Timestamper.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address constant CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    ICreateX public createX;

    function setUp() public {
        createX = ICreateX(CREATE_X);
    }

    function run() public broadcast {
        address witnessProxy = createX.deployCreate2(
            keccak256("WITNESS_ERC1967_PROXY"),
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    witnessImplementation,
                    abi.encodeCall(Endorser.initialize, (msg.sender))
                )
            )
        );
        console.log("Witness contract deployed to %s", address(witnessProxy));

        address endorserProxy = createX.deployCreate2(
            keccak256("ENDORSER_ERC1967_PROXY"),
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(
                    endorserImplementation,
                    abi.encodeCall(Endorser.initialize, (msg.sender))
                )
            )
        );
        console.log("Endorser contract deployed to %s", address(endorserProxy));
    }
}

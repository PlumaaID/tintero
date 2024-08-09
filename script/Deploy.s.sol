// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseScript} from "./utils/Base.s.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Endorser} from "~/Endorser.sol";
import {IWitness} from "@WitnessCo/interfaces/IWitness.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address constant PLUMAA_DEPLOYER_EOA =
        0x00560ED8242bF346c162c668487BaCD86cc0B8aa;
    address constant PLUMAA_MULTISIG =
        0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa;
    address constant CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    ICreateX public createX;

    // From https://docs.witness.co/additional-notes/deployments
    IWitness constant WITNESS =
        IWitness(0x0000000e143f453f45B2E1cCaDc0f3CE21c2F06a);

    function setUp() public {
        createX = ICreateX(CREATE_X);
    }

    function run() public broadcast {
        address manager = _deployManager();
        _deployEndorser(manager);
    }

    function _deployManager() internal returns (address) {
        bytes memory code = abi.encodePacked(
            type(AccessManager).creationCode,
            abi.encode(PLUMAA_MULTISIG)
        );
        address manager = createX.deployCreate2(
            _toSalt(0xc71e67c14a7af703583551),
            code
        );
        console2.log("AccessManager contract deployed to %s", address(manager));
        assert(0x00BA769e700657aDC3bB4Fb62315034bf65105aA == manager);
        return manager;
    }

    function _deployEndorser(address manager) internal returns (address) {
        address endorserImplementation = createX.deployCreate2(
            _toSalt(0x22d7b0559435ee036d0fad),
            type(Endorser).creationCode
        );
        bytes memory code = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(
                endorserImplementation,
                abi.encodeCall(Endorser.initialize, (manager, WITNESS))
            )
        );
        address endorserProxy = createX.deployCreate2(
            _toSalt(0xb14cb019d151f2038a6a61),
            code
        );
        console2.log(
            "Endorser contract deployed to %s",
            address(endorserProxy)
        );
        assert(0x009079A0E192A3cAebbfC96db1D22e6Aa4458CaA == endorserProxy);
        return endorserProxy;
    }

    function _toSalt(bytes11 mined) internal pure returns (bytes32) {
        return
            (bytes32(mined) >> 168) |
            (bytes32(0x00) >> 160) | // No cross-chain redeployment protection
            bytes32(bytes20(PLUMAA_DEPLOYER_EOA));
    }
}

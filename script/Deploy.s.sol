// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {console2} from "forge-std/console2.sol";
import {AccessManager} from "@openzeppelin/contracts/access/manager/AccessManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BaseScript} from "./utils/Base.s.sol";
import {ICreateX} from "createx/ICreateX.sol";
import {Endorser} from "~/Endorser.sol";
import {TinteroVault} from "~/TinteroVault.sol";
import {IWitness} from "@WitnessCo/interfaces/IWitness.sol";

/// @dev See the Solidity Scripting tutorial: https://book.getfoundry.sh/tutorials/solidity-scripting
contract Deploy is BaseScript {
    address public constant PLUMAA_DEPLOYER_EOA =
        0x00560ED8242bF346c162c668487BaCD86cc0B8aa;
    address public constant CREATE_X =
        0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
    ICreateX public createX;

    address public constant MANAGER_ADDRESS =
        0x0000593Daa1e9E24FEe19AF6B258A268c97aAAAa;
    address public constant ENDORSER_ADDRESS =
        0x0000c908D1104caD2867Ec2A8Bb178D78C9bAaaa;
    address public constant TINTERO_VAULT_USDC_ARBITRUM =
        0x0000c635B91a73dd4Ee11e27c216Ab866AbCaAAa;
    address public constant TINTERO_VAULT_USDC_ARBITRUM_SEPOLIA =
        0x00001E99B72BAcD5b563fBB5d74CBe1d3e95AAaA;

    // From https://docs.witness.co/additional-notes/deployments
    IWitness public constant WITNESS =
        IWitness(0x0000000e143f453f45B2E1cCaDc0f3CE21c2F06a);

    function setUp() public {
        createX = ICreateX(CREATE_X);
    }

    function run() public broadcast {
        address manager = _deployManager();
        _deployEndorser(manager);
        _deployTinteroVaultUSDC(manager);
    }

    function _deployManager() internal returns (address) {
        if (MANAGER_ADDRESS.code.length > 0) return MANAGER_ADDRESS; // Already deployed
        bytes memory code = abi.encodePacked(
            type(AccessManager).creationCode,
            abi.encode(PLUMAA_DEPLOYER_EOA)
        );
        address manager = createX.deployCreate2(
            _toSalt(0x9c3e14f6e59be203389372),
            code
        );
        console2.log("AccessManager contract deployed to %s", address(manager));
        assert(MANAGER_ADDRESS == manager);
        return manager;
    }

    function _deployEndorser(address manager) internal returns (address) {
        if (ENDORSER_ADDRESS.code.length > 0) return ENDORSER_ADDRESS; // Already deployed
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
        console2.logBytes32(keccak256(code));
        address endorserProxy = createX.deployCreate2(
            _toSalt(0x0dfbeb937a613901a27902),
            code
        );
        assert(ENDORSER_ADDRESS == endorserProxy);
        return endorserProxy;
    }

    function _deployTinteroVaultUSDC(
        address manager
    ) internal returns (address) {
        address usdc;
        bytes11 mined;
        address expectedAddress;

        if (block.chainid == 42161) {
            if (TINTERO_VAULT_USDC_ARBITRUM.code.length > 0)
                return TINTERO_VAULT_USDC_ARBITRUM; // Already deployed
            usdc = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
            mined = 0x9bcac83a3b705903cddb3e;
            expectedAddress = TINTERO_VAULT_USDC_ARBITRUM;
        }
        if (block.chainid == 421614) {
            if (TINTERO_VAULT_USDC_ARBITRUM_SEPOLIA.code.length > 0)
                return TINTERO_VAULT_USDC_ARBITRUM_SEPOLIA; // Already deployed
            usdc = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
            mined = 0x8a4fa73e0d365200cd48ab;
            expectedAddress = TINTERO_VAULT_USDC_ARBITRUM_SEPOLIA;
        }
        if (usdc == address(0)) {
            console2.log("USDC address not found for chain %d", block.chainid);
            return address(0);
        }

        bytes memory code = abi.encodePacked(
            type(TinteroVault).creationCode,
            abi.encode(usdc, manager)
        );
        console2.logBytes32(keccak256(code));
        address tinteroVaultUSDC = createX.deployCreate2(_toSalt(mined), code);
        assert(expectedAddress == tinteroVaultUSDC);
        return tinteroVaultUSDC;
    }

    function _toSalt(bytes11 mined) internal pure returns (bytes32) {
        return
            (bytes32(mined) >> 168) |
            (bytes32(0x00) >> 160) | // No cross-chain redeployment protection
            bytes32(bytes20(PLUMAA_DEPLOYER_EOA));
    }
}

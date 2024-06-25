// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/// @title Witnesser
///
/// @notice A contract to provide data conservation services by witnessing hashes of digital documents.
/// It can be used to replace a NOM-151 timestamping service.
///
/// @custom:security-contact security@plumaa.id
contract Witnesser is Initializable, AccessManagedUpgradeable, UUPSUpgradeable {
    // keccak256(abi.encode(uint256(keccak256("PlumaaID.storage.Witnesser")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant WITNESSER_STORAGE =
        0x2f67eca4febef59bb0ea363823ce190b8b9971ac293e7fccb4e149c65e726f00;

    event Witnessed(bytes32 indexed digest, uint48 timestamp);

    struct WitnesserStorage {
        mapping(bytes32 => uint48 timestamp) _witnessed;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract setting an initial authority
    function initialize(address initialAuthority) external initializer {
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();
    }

    /// @notice Returns the timestamp at which a hash was witnessed
    function witnessedAt(bytes32 digest) external view returns (uint48) {
        return _getWitnesserStorage()._witnessed[digest];
    }

    /// @notice Witnesses a hash and sets a timestamp for data conservation
    function witness(bytes32 digest) external restricted {
        uint48 timestamp = SafeCast.toUint48(block.timestamp);
        _getWitnesserStorage()._witnessed[digest] = timestamp;
        emit Witnessed(digest, timestamp);
    }

    /// @notice Get EIP-7201 storage
    function _getWitnesserStorage()
        private
        pure
        returns (WitnesserStorage storage $)
    {
        assembly {
            $.slot := WITNESSER_STORAGE
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}
}

// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Witnesser} from "./Witnesser.sol";

/// @title Endorser
///
/// @notice A contract to track digital endorsements according to Mexican comercial and debt instruments law. This contract
/// allows for any user to mint a new token by providing the hash of the digital document that's endorsed and a proof witnessed
/// by the Witnesser. Privacy is ensured by only tracking the hash of the document, and not the document itself.
///
/// Approvals are not enabled since there's not regulatory clarity on the matter. Contract may upgrade to enable approvals.
///
/// NOTE: Property is tied to regular Ethereum addresses. It's the responsibility of the developer to implement a robust
/// legal framework to ensure the link between the owner and such address.
///
/// @custom:security-contact security@plumaa.id
contract Endorser is
    Initializable,
    ERC721Upgradeable,
    ERC721BurnableUpgradeable,
    AccessManagedUpgradeable,
    UUPSUpgradeable
{
    using BitMaps for BitMaps.BitMap;

    // keccak256(abi.encode(uint256(keccak256("PlumaaID.storage.Endorser")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant WITNESSER_STORAGE =
        0xd4afa66895d5fdd6c8f53a8b47d14ebe8786dd18400174140b53bbb9a8838e00;

    struct EndorserStorage {
        BitMaps.BitMap _nullifier;
        Witnesser _witnesser;
    }

    error UnsupportedOperation();
    error InvalidProof();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract setting an initial authority and a Witnesser contract
    function initialize(
        address initialAuthority,
        address _witnesser
    ) public initializer {
        __ERC721_init("Endorser", "END");
        __ERC721Burnable_init();
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();
        _getEndorserStorage()._witnesser = Witnesser(_witnesser);
    }

    /// @notice Returns the Witnesser contract
    function witnesser() public view returns (Witnesser) {
        return _getEndorserStorage()._witnesser;
    }

    /// @notice Mints a new token for the provided `to` address if the proof is valid and nullifies it so it can't be used again.
    function mint(
        address to,
        bytes32 digest,
        bytes32 root,
        bytes32[] memory proof
    ) external {
        _validateAndNullifyProof(to, digest, root, proof);
        _safeMint(to, uint256(digest));
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://api.plumaa.id/protocol/metadata/";
    }

    /// @notice Disables token approvals
    function _approve(address, uint256, address, bool) internal pure override {
        revert UnsupportedOperation();
    }

    /// @notice Disables approvals
    function _setApprovalForAll(address, address, bool) internal pure override {
        revert UnsupportedOperation();
    }

    /// @notice Checks whether a proof is valid and nullifies it so it can't be used again.
    ///
    /// Requirements:
    ///
    /// - The leaf produced by the `digest` and `to` must derive to the `root` using the `proof`.
    /// - The `root` was witnessed by the Witnesser.
    /// - The `leaf` was not nullified before.
    function _validateAndNullifyProof(
        address to,
        bytes32 digest,
        bytes32 root,
        bytes32[] memory proof
    ) internal {
        bytes32 leaf = _leaf(to, digest);
        bytes memory data = abi.encodeCall(Witnesser.witnessedAt, (leaf));
        (, bytes32 timestamp) = _callReturnScratchBytes32(
            address(witnesser()),
            0,
            data
        );
        if (
            !MerkleProof.verify(proof, root, leaf) || // invalid proof
            _getEndorserStorage()._nullifier.get(uint256(leaf)) || // not nullified
            timestamp == 0 // witnessed
        ) {
            revert InvalidProof();
        }
        _getEndorserStorage()._nullifier.set(uint256(leaf));
    }

    /// @notice Leaf hash. Uses an opinionated double hashing scheme.
    function _leaf(address to, bytes32 digest) internal pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(to, digest))));
    }

    /// @notice Get EIP-7201 storage
    function _getEndorserStorage()
        private
        pure
        returns (EndorserStorage storage $)
    {
        assembly {
            $.slot := WITNESSER_STORAGE
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override restricted {}

    /// @dev Performs a Solidity function call using a low level `call` and returns the first 32 bytes of the result
    /// in the scratch space of memory. Useful for functions that return a single-word value.
    ///
    /// WARNING: Do not assume that the result is zero if `success` is false. Memory can be already allocated
    /// and this function doesn't zero it out.
    function _callReturnScratchBytes32(
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (bool success, bytes32 result) {
        assembly ("memory-safe") {
            success := call(
                gas(),
                target,
                value,
                add(data, 0x20),
                mload(data),
                0,
                0x20
            )
            result := mload(0)
        }
    }
}

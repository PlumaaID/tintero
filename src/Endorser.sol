// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {WitnessConsumer} from "@WitnessCo/WitnessConsumer.sol";

/// @title Endorser
///
/// @notice A contract to track digital endorsements according to Mexican comercial and debt instruments law. This contract
/// allows for any user to mint a new token by providing the hash of the digital document a provenance proof checked against
/// the [Witness](https://docs.witness.co/api-reference/solidity/Witness.sol). Privacy is ensured by only tracking the hash of the document,
/// and not the document itself.
///
/// Approvals are not enabled since there's no regulatory clarity on the matter. Contract may upgrade to enable approvals.
///
/// NOTE: Property is tied to regular Ethereum addresses. It's the responsibility of the developer to implement a robust
/// regulatory framework to ensure the link between the owner and such address.
///
/// @author Ernesto García
///
/// @custom:security-contact security@plumaa.id
contract Endorser is
    Initializable,
    ERC721Upgradeable,
    ERC721BurnableUpgradeable,
    AccessManagedUpgradeable,
    UUPSUpgradeable,
    WitnessConsumer
{
    using BitMaps for BitMaps.BitMap;

    // keccak256(abi.encode(uint256(keccak256("PlumaaID.storage.Endorser")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ENDORSER_STORAGE =
        0xd4afa66895d5fdd6c8f53a8b47d14ebe8786dd18400174140b53bbb9a8838e00;

    uint64 internal constant PROVENANCE_AUTHORIZER_ROLE =
        uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")));

    struct EndorserStorage {
        BitMaps.BitMap _nullifier;
        IWitness _witness;
    }

    error UnsupportedOperation();
    error AlreadyClaimed();
    error MismatchedLeaf();
    error InvalidAuthorization();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Leaf hash. Uses SHA256 according to the algorithms approved by the Mexican government.
    function getProvenanceHash(
        bytes memory data
    ) public pure virtual override returns (bytes32) {
        return sha256(data);
    }

    /// @notice Initializes the contract setting an initial authority and a Witness contract
    function initialize(
        address initialAuthority,
        IWitness witness
    ) public initializer {
        __ERC721_init("Endorser", "END");
        __ERC721Burnable_init();
        __AccessManaged_init(initialAuthority);
        __UUPSUpgradeable_init();
        _getEndorserStorage()._witness = witness;
    }

    /// @inheritdoc WitnessConsumer
    function WITNESS() public view virtual override returns (IWitness) {
        return _getEndorserStorage()._witness;
    }

    /// @notice Mints a new token for the provided `to` address if the proof is valid and nullifies it so it can't be used again.
    function mint(
        address to,
        bytes32 digest,
        Proof calldata proof,
        address authorizer,
        bytes calldata authorizerSignature
    ) external {
        _validateAndNullifyProof(
            to,
            digest,
            proof,
            authorizer,
            authorizerSignature
        );
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
    /// - The `root` was witnessed by the Witness.
    /// - The `leaf` was not nullified before.
    function _validateAndNullifyProof(
        address to,
        bytes32 digest,
        Proof calldata proof,
        address authorizer,
        bytes calldata authorizerSignature
    ) internal {
        EndorserStorage storage $ = _getEndorserStorage();
        bytes32 leaf = getProvenanceHash(abi.encode(to, digest));

        // Sanity check
        if (leaf != proof.leaf) revert MismatchedLeaf();

        // Already nullified
        if ($._nullifier.get(uint256(leaf))) revert AlreadyClaimed();

        // Verify authorizer signature
        if (
            !SignatureChecker.isValidSignatureNow(
                authorizer,
                MessageHashUtils.toEthSignedMessageHash(leaf),
                authorizerSignature
            )
        ) revert InvalidAuthorization();

        // Check if the authorizer is a member of the PROVENANCE_AUTHORIZER_ROLE
        (bool isMember, ) = IAccessManager(authority()).hasRole(
            PROVENANCE_AUTHORIZER_ROLE,
            authorizer
        );
        if (!isMember) revert InvalidAuthorization();

        // Nullify leaf
        $._nullifier.set(uint256(leaf));

        // Reverts on invalid proof
        this.verifyProof(proof);
    }

    /// @notice Get EIP-7201 storage
    function _getEndorserStorage()
        private
        pure
        returns (EndorserStorage storage $)
    {
        assembly ("memory-safe") {
            $.slot := ENDORSER_STORAGE
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
    function _callReturnBytes32(
        address target,
        bytes memory data
    ) internal returns (bool success, bytes32 result) {
        assembly ("memory-safe") {
            success := call(
                gas(),
                target,
                0,
                add(data, 0x20),
                mload(data),
                0,
                0x20
            )
            result := mload(0)
        }
    }
}

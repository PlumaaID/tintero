// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.20;

import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {ERC721BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {IAccessManager} from "@openzeppelin/contracts/access/manager/IAccessManager.sol";
import {AccessManagedUpgradeable} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagedUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IWitness, Proof} from "@WitnessCo/interfaces/IWitness.sol";
import {WitnessConsumer} from "@WitnessCo/WitnessConsumer.sol";

/// @title Endorser
///
/// @notice A contract to track digital endorsements according to Mexican comercial and debt instruments law. This contract
/// allows for any user to mint a new token by providing the hash of the digital document a provenance proof checked against
/// the [Witness](https://docs.witness.co/api-reference/solidity/Witness.sol) and a valid signature from an authorizer.
/// Privacy is ensured by only tracking the hash of the document, and not the document itself.
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
    EIP712Upgradeable,
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

    struct MintRequestData {
        address authorizer;
        address to;
        bytes signature;
    }

    bytes32 internal constant _MINT_AUTHORIZATION_TYPEHASH =
        keccak256("MintRequest(bytes32 leaf,address to)");

    struct EndorserStorage {
        BitMaps.BitMap _nullifier;
        IWitness _witness;
    }

    error AlreadyClaimed();
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
        __EIP712_init("Endorser", "1");
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
        MintRequestData calldata request,
        Proof calldata proof
    ) external {
        _validateAndNullifyProof(request, proof);
        _safeMint(request.to, uint256(proof.leaf));
    }

    /// @notice Sets the Witness contract
    /// NOTE: Witness is set by default to the mainnet address, it should be updated
    /// to the correct address before deployment when deploying to testnets.
    function setWitness(IWitness witness) external restricted {
        _getEndorserStorage()._witness = witness;
    }

    function _baseURI() internal pure override returns (string memory) {
        return "https://api.plumaa.id/protocol/endorser/metadata/";
    }

    /// @notice Checks whether a proof is valid and nullifies it so it can't be used again.
    ///
    /// Requirements:
    ///
    /// - The leaf was not nullified before.
    /// - The mint request was signed by an authorizer.
    /// - The authorizer is a member of the PROVENANCE_AUTHORIZER_ROLE.
    /// - The proof is valid according to the Witness contract.
    function _validateAndNullifyProof(
        MintRequestData calldata request,
        Proof calldata proof
    ) internal {
        EndorserStorage storage $ = _getEndorserStorage();

        // Already nullified
        if ($._nullifier.get(uint256(proof.leaf))) revert AlreadyClaimed();

        // Verify authorizer signature
        if (
            !SignatureChecker.isValidSignatureNow(
                request.authorizer,
                _hashTypedDataV4(
                    keccak256(
                        abi.encode(
                            _MINT_AUTHORIZATION_TYPEHASH,
                            proof.leaf,
                            request.to
                        )
                    )
                ),
                request.signature
            )
        ) revert InvalidAuthorization();

        // Check if the authorizer is a member of the PROVENANCE_AUTHORIZER_ROLE
        (bool isMember, ) = IAccessManager(authority()).hasRole(
            PROVENANCE_AUTHORIZER_ROLE,
            request.authorizer
        );
        if (!isMember) revert InvalidAuthorization();

        // Nullify leaf
        $._nullifier.set(uint256(proof.leaf));

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
}

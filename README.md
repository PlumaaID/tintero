# Plumaa ID | Protocol

<img src="./images/logo.png" width="150" alt="Plumaa ID">

Plumaa ID Protocol is a set of open-source smart contracts that enable organizations to comply with the requirements of data preservation and non-interrumpted chain of endorsements under Mexican commercial and debt instruments law.

The protocol includes one main component:

- Endorser: An ERC721 token that uses a document hash as a token id. The chain of endorsements is represented by the transfer of the token and each transfer complies with data preservation requirements with the block timestamp, and the chain of endorsements is obtained from the previous token holder.

The content of documents remains private since the system only track hashes.

### Getting started

```
make
```

### Deployments

| Network          | ChainID | Access Manager                             | Endorser Proxy                             |
| ---------------- | ------- | ------------------------------------------ | ------------------------------------------ |
| Arbitrum         | 42161   | 0x00BA769e700657aDC3bB4Fb62315034bf65105aA | 0x009079A0E192A3cAebbfC96db1D22e6Aa4458CaA |
| Arbitrum Sepolia | 421614  | 0x00BA769e700657aDC3bB4Fb62315034bf65105aA | 0x009079A0E192A3cAebbfC96db1D22e6Aa4458CaA |

## Roles

- PROVENANCE_AUTHORIZER: 12236269664351332516 (`uint64(bytes8(keccak256("PlumaaID.PROVENANCE_AUTHORIZER")))`)

### Role mapping

| Role     | Function signature                | Selector | Target contract                            |
| -------- | --------------------------------- | -------- | ------------------------------------------ |
| UPGRADER | `upgradeToAndCall(address,bytes)` | 4f1ef286 | 0x009079A0E192A3cAebbfC96db1D22e6Aa4458CaA |

### Role members

| Role                  | Address                                    | Execution Delay |
| --------------------- | ------------------------------------------ | --------------- |
| PROVENANCE_AUTHORIZER | 0xD4FAa2Bcdd1A438C9E69699166eDc92E65954ED7 | 0               |
| UPGRADER              | 0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa | 259200 (3 days) |

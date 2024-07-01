# Plumaa ID | Protocol

<img src="./images/logo.png" width="150" alt="Plumaa ID">

Plumaa ID Protocol is a set of open-source smart contracts that enable organizations to comply with the requirements of data preservation and non-interrumpted chain of endorsements under Mexican commercial and debt instruments law.

The protocol includes two main components:

- Witness: A smart contract that witnesses `bytes32` hashes of documents to guarantee data preservation. A witness entry is similar to a NOM-151.
- Endorser: An ERC721 token that uses a document hash as a token id. The chain of endorsements is represented by the transfer of the token and each transfer complies with data preservation requirements with the block timestamp, and the chain of endorsements is obtained from the previous token holder.

The content of documents remains private since the system only track hashes.

### Getting started

```
make
```

### Deployments

| Network          | ChainID | Access Manager                             | Witness Proxy                              | Endorser Proxy                             |
| ---------------- | ------- | ------------------------------------------ | ------------------------------------------ | ------------------------------------------ |
| Arbitrum         | 42161   | 0x000fcD69be90B1ABCAfC40D47Ba3f4eE628725Aa | 0x008CFe0543dB8d5000219433dca6E59D482177Aa | 0x0065313718d91863De3cB78A5C188990A67093Aa |
| Arbitrum Sepolia | 421614  | 0x000fcD69be90B1ABCAfC40D47Ba3f4eE628725Aa | 0x008CFe0543dB8d5000219433dca6E59D482177Aa | 0x0065313718d91863De3cB78A5C188990A67093Aa |

## Roles

- RELAYER: 12344232774587232509 (`uint64(bytes8(keccak256('RELAYER')))`)
- UPGRADER: 11967657057449934008 (`uint64(bytes8(keccak256('UPGRADER')))`)

### Role mapping

| Role     | Function signature                | Selector | Target contract                            |
| -------- | --------------------------------- | -------- | ------------------------------------------ |
| RELAYER  | `witness(bytes32)`                | 114ee197 | 0x008CFe0543dB8d5000219433dca6E59D482177Aa |
| UPGRADER | `upgradeToAndCall(address,bytes)` | 4f1ef286 | 0x008CFe0543dB8d5000219433dca6E59D482177Aa |
| UPGRADER | `upgradeToAndCall(address,bytes)` | 4f1ef286 | 0x0065313718d91863De3cB78A5C188990A67093Aa |

### Role members

| Role     | Address                                    | Execution Delay |
| -------- | ------------------------------------------ | --------------- |
| RELAYER  | 0xD4FAa2Bcdd1A438C9E69699166eDc92E65954ED7 | 0               |
| UPGRADER | 0x00fA8957dC3D2f6081360056bf2f6d4b5f1a49aa | 259200 (3 days) |

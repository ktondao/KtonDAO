# KtonDAO 

## Addresses

### Ethereum mainnet (chain ID 1)

| Contract | Address |
|----------|---------|
| KTON (underlying token) | [0x9F284E1337A815fe77D2Ff4aE46544645B20c5ff](https://etherscan.io/address/0x9F284E1337A815fe77D2Ff4aE46544645B20c5ff) |
| gKTON | [0xc75c2EC60Bf276B8C0A5Af129114E344bBd93f14](https://etherscan.io/address/0xc75c2EC60Bf276B8C0A5Af129114E344bBd93f14) |
| KtonDAOV3 (proxy) | [0x86EEaa7c5327809c47a35792eAd86feA311194F5](https://etherscan.io/address/0x86EEaa7c5327809c47a35792eAd86feA311194F5) |
| KtonDAOV3 (implementation) | [0x704B83AaABAed7F85375547F15eCA8F3B3ac893c](https://etherscan.io/address/0x704B83AaABAed7F85375547F15eCA8F3B3ac893c) |
| Timelock | [0xEE25d900b1cF9f261Bba614695fb6e987d1bc6A2](https://etherscan.io/address/0xEE25d900b1cF9f261Bba614695fb6e987d1bc6A2) |

### Legacy cross-chain deployments

|  Contract            | Canonical Cross-chain Deployment Address   |
|----------------------|--------------------------------------------|
|  KTONStakingRewards  | 0x000000000419683a1a03AbC21FC9da25fd2B4dD7 |
|  RewardsDistribution | 0x000000000Ae5DB7BDAf8D071e680452e33d91Dd5 |
|  modlda/trsry        | 0x6d6f646c64612f74727372790000000000000000 |
|  gKTON               | 0xB633Ad1142941CA2Eb9C350579cF88BbE266660D |
|  KtonDAO             | 0xaAC63c40930cCAF99603229F6381D82966b145ef |
|  Timelock            | 0x08837De0Ae21C270383D9F2de4DB03c7b1314632 |
|  KtonDAOVault        | 0x652182C6aBc0bBE41b5702b05a26d109A405EAcA |
|  KtonDAO Treasury Manager Darwinia       | 0x9497c0474c0Bba76942AD553DA91F4e52df45E8f |
|  KtonDAO Treasury Manager Other Network         | 0x86394271Bb8C604b1F4E692624C45e751Cc7577B |

## Deploy GKTON and governance

`script/DeployGKTON.s.sol` deploys a fresh governance stack:

- `src/governance/GKTON.sol` directly, without a proxy.
- `KtonDAOV3` behind a transparent proxy, initialized with the new gKTON and timelock.
  V3 initializes quorum to 3,000 KTON; later changes require an approved governance
  proposal calling `updateQuorum`. The constructor takes no quorum argument.
  Quorum history follows the [GovernorVotesQuorum reference implementation](https://github.com/ringdao-community-guild/contracts/blob/main/src/gov/GovernorVotesQuorum.sol),
  adapted to OpenZeppelin 5 with `Checkpoints.Trace208` and proxy initialization.
  `quorum()` returns the current value; `quorum(timepoint)` returns the value at
  that snapshot, so updates preserve the quorum used by past proposal snapshots.
- `KtonTimelockController`, which owns the DAO's ProxyAdmin. The DAO receives the
  proposer, canceller, and executor roles; the deployer's temporary admin role is
  renounced after setup.

This script supports Ethereum mainnet only (chain ID 1). Governance parameters
match [KtonDAO on DeGov](https://kton.degov.ai/), verified against its Darwinia
contracts at block 13,736,436 on 2026-11-03: DAO name `KtonDAO`, quorum 3,000 KTON,
proposal threshold 20 KTON, zero voting delay, 7-day voting period (604,800 seconds),
and 1-day timelock delay (86,400 seconds). Amounts assume 18 token decimals.
The reference governor is `0xaAC63c40930cCAF99603229F6381D82966b145ef` and its
timelock is `0x08837De0Ae21C270383D9F2de4DB03c7b1314632`.
The page labels the zero-second voting delay as "a few seconds"; the script uses
the exact on-chain value, `0`.

The GKTON name and symbol are `Governance KTON` and `gKTON`. This wrapper has no
staking rewards, so this script does not deploy the legacy rewards vault.

The wrapper is deployed from its compiled artifact. Run `forge build` before
running this script.

Set `ETH_RPC_URL` to an Ethereum mainnet RPC endpoint. The underlying KTON token
address defaults to `0x9F284E1337A815fe77D2Ff4aE46544645B20c5ff`.
Set `KTON_TOKEN` only when overriding this address.

Dry run (no transactions broadcast):

```sh
forge script script/DeployGKTON.s.sol:DeployGKTONScript --rpc-url "$ETH_RPC_URL"
```

Deploy using a Foundry keystore account and an `ETHERSCAN_API_KEY` for verification:

```sh
forge script script/DeployGKTON.s.sol:DeployGKTONScript --rpc-url "$ETH_RPC_URL" --account <account-name> --broadcast --verify --etherscan-api-key "$ETHERSCAN_API_KEY"
```

The script prints the chain ID, underlying KTON address, gKTON address, DAO proxy
and implementation addresses, and timelock address.

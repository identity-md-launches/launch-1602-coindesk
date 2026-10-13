# Coindesk (COINDESK)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum.

| Parameter | Value |
| --- | --- |
| Solidity contract | `CoindeskToken` (`src/CoindeskToken.sol`) |
| `name()` | `Coindesk` |
| `symbol()` | `COINDESK` |
| `decimals()` | `18` |
| Total supply | `1,000,000,000 COINDESK` = `1000000000000000000000000000` minor units (1e27) |
| Constructor arguments | none |
| Mint | once, in the constructor, the whole supply to `msg.sender` (the deployer) |
| Owner / admin | none |

## Behaviour

- Standard ERC-20 built on OpenZeppelin Contracts v5.5.0 `ERC20` (vendored under `lib/`).
- The whole supply is minted once to the deployer in the constructor. There is no `mint`, no minter role, no
  owner, no `Ownable`, no proxy and no initializer, so the supply can never grow after deployment.
- No transfer tax, no burn-on-transfer, no reflections, no blacklist, no pause, no freeze. Every `transfer` and
  `transferFrom` moves exactly the amount it is given, and only the holder (or a spender it approved) can move a
  balance.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, and the contract rejects ether.
- All library code the token uses is `internal`, so the built bytecode has no link placeholders.

## Assumptions

- **The deployer receives the supply.** `msg.sender` of the constructor holds all 1e27 minor units. On the
  IdentityMD launch that is the ProjectFactory, which then pays the supply out. If the token is deployed by any
  other means, whoever (or whatever contract) creates it holds everything; a deployment from inside a contract
  sends the supply to that contract, not to the transaction's origin.
- **Nothing is reserved.** No allocation, vesting, treasury or team share is encoded in the token. All
  distribution happens after deployment through ordinary transfers by the holder of the supply.
- **The supply is final.** The brief asks for one mint of 1,000,000,000 tokens with 18 decimals and nothing
  more. There is deliberately no way to issue more; if the requester later needs an inflating token, that is a
  different contract.
- **No burn function is exposed.** The brief does not ask for one. Holders can still send tokens to an address
  nobody controls, which is their own business; the token itself never reduces anyone's balance.

## Launch (IdentityMD custom token)

These values are decided by the launch and are recorded in `launch.json` by the manifest step after this work is
accepted. They are listed here for the reviewer; this repository does not contain a `launch.json`.

- Chain: Ethereum mainnet (chain id 1).
- Token contract name: `CoindeskToken`; `token.totalSupply`: `1000000000000000000000000000`; decimals `18`;
  constructor arguments: `[]`.
- Application contracts: none.
- Pool: paired with IMD (`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`), fee `12500`, tick spacing `60`,
  initial price `79228162514264337593543950336`.
- Economics (copied verbatim from the job): `poolBps` 8800, `initialMarketCapWei` 2500000000000000000000 (2,500
  IMD), `remainderTo` `0x8d79927b9ee26e30ff9b0a1973f6d54a1431cf91`.
- The factory holds the whole supply after the constructor runs, forwards 10% to the launch's
  MerkleDistributor, seeds 88% into the Uniswap v4 pool, and forwards the remaining 2% to `remainderTo`. All of
  these are plain transfers and arrive whole, as `test_launchFlowsArriveWhole` demonstrates.

### After launch

There is nothing to configure. The token has no owner-settable values, no setters and no privileged roles.

## Operational responsibilities

- **The holder of the supply is responsible for its distribution.** On the launch that is the factory for the
  launch flows, and `remainderTo` afterwards for the requester's 2%. The token cannot recover tokens sent to a
  wrong address, to the token contract itself or to a contract that cannot move them.
- **Allowance hygiene is the holder's.** Approvals are standard ERC-20: an unlimited approval stays unlimited
  until the holder changes it. Holders should approve only what they intend to spend. `approve` overwrites the
  previous value, so a race on changing a non-zero allowance exists as in every ERC-20; set it to zero first if
  that matters.
- **No emergency controls exist.** There is nobody who can pause, freeze or seize. If the token must ever be
  replaced, that is a new deployment and a migration, not an upgrade.
- **Explorer verification** of the deployed source is the launch deployer's step, after deployment, with the
  compiler settings in `foundry.toml` (solc 0.8.26, optimizer on, 200 runs, `bytecode_hash = "none"`,
  `cbor_metadata = false`, EVM `cancun`).

## Security notes

Checked against the pinned eth-security reference (`.imd/reads/skills/eth-security`):

- Decimals are 18 and fixed; there is no cross-token arithmetic in the contract.
- No reentrancy surface: the token makes no external calls and holds no ether.
- No access control to misconfigure: there are no privileged functions.
- No proxy, no `delegatecall`, no upgradeability.
- Input validation is OpenZeppelin's: transfers to the zero address, approvals of the zero spender, transfers
  above balance and above allowance revert with typed ERC-6093 errors; each is covered by a failing-path test.
- Tools run: `forge build`, `forge test` (unit and fuzz, 256 runs per fuzz test) and `forge fmt --check`.
  Slither and Mythril were not available in this environment and did not run. Passing tests are not an audit;
  an independent adversarial review before release is still the launch's responsibility.

## Build and test

```
forge build
forge test
forge fmt --check
```

The tests read no environment variables and do not depend on which address runs them, so they can run in any
order, in parallel and with an empty environment.

## Reference deployment script

`script/DeployCoindeskToken.s.sol` deploys the token with no configuration. `deploy()` is the function the tests
call; `run()` wraps it in a broadcast for a fork or private chain:

```
forge script script/DeployCoindeskToken.s.sol --rpc-url <rpc> --broadcast
```

The IdentityMD launch does not use this script: the factory deploys the token from the built bytecode and holds
the supply. The script is provided for review and reproduction only. No keys are stored in this repository and
nothing here broadcasts a transaction on its own.

## Layout

```
foundry.toml                      compiler pins (solc 0.8.26, bytecode_hash none, ffi off, no fs permissions)
src/CoindeskToken.sol             the token
script/DeployCoindeskToken.s.sol  reference deploy script
test/CoindeskToken.t.sol          token tests: metadata, supply, transfers, failures, fixed supply, launch flows, fuzz
test/DeployCoindeskToken.t.sol    deploy script tests
lib/forge-std                     vendored test framework (plain files)
lib/openzeppelin-contracts        vendored OpenZeppelin Contracts v5.5.0 subset (plain files)
```

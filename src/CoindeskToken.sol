// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Coindesk (COINDESK)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 COINDESK (18 decimals) is minted once, in
///         the constructor, to the deployer (`msg.sender`). Nothing can mint afterwards, there is no owner, no
///         pause, no blacklist, no transfer tax and no burn hook: every transfer moves exactly what it says.
/// @dev On a launch the deployer is the IdentityMD ProjectFactory, which receives the supply and pays all of it
///      out (swarm distributor, pool seed, requester remainder). The constructor takes no arguments and calls no
///      other contract, so it deploys identically on an empty chain. The contract name is the launch's
///      Solidity identifier (`CoindeskToken`, 13 characters); the token's own name and symbol are what
///      `name()` and `symbol()` return.
contract CoindeskToken is ERC20 {
    /// @notice The token's ERC-20 name.
    string public constant NAME = "Coindesk";

    /// @notice The token's ERC-20 symbol.
    string public constant SYMBOL = "COINDESK";

    /// @notice Decimals the supply is expressed in.
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply ever to exist, in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints the whole fixed supply to the deployer.
    /// @dev `ERC20._mint` emits `Transfer(address(0), msg.sender, TOTAL_SUPPLY)`. There is no other mint path.
    constructor() ERC20(NAME, SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}

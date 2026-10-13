// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {CoindeskToken} from "../src/CoindeskToken.sol";
import {DeployCoindeskToken} from "../script/DeployCoindeskToken.s.sol";

contract DeployCoindeskTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    function test_deployMintsSupplyToTheScriptCaller() public {
        DeployCoindeskToken deployer = new DeployCoindeskToken();
        CoindeskToken token = deployer.deploy();
        // `deploy()` creates the token from inside the script contract, so the script contract is `msg.sender`
        // in the constructor and holds the supply, exactly as the factory will on the launch.
        assertEq(token.balanceOf(address(deployer)), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.name(), "Coindesk");
        assertEq(token.symbol(), "COINDESK");
        assertEq(token.decimals(), 18);
    }

    function test_twoDeploymentsAreIndependent() public {
        DeployCoindeskToken deployer = new DeployCoindeskToken();
        CoindeskToken first = deployer.deploy();
        CoindeskToken second = deployer.deploy();
        assertTrue(address(first) != address(second));
        assertEq(first.totalSupply(), EXPECTED_SUPPLY);
        assertEq(second.totalSupply(), EXPECTED_SUPPLY);
        assertEq(first.balanceOf(address(deployer)), EXPECTED_SUPPLY);
        assertEq(second.balanceOf(address(deployer)), EXPECTED_SUPPLY);
    }
}

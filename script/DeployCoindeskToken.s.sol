// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {CoindeskToken} from "../src/CoindeskToken.sol";

/// @title Deploy script for CoindeskToken
/// @notice Reviewable reference deployment. The IdentityMD launch does not run this script: the factory
///         deploys the token from its built bytecode and the whole supply goes to the factory. This script
///         exists so the deployment can be reproduced and reviewed on a fork or a private chain.
/// @dev The token takes no constructor arguments, so there is no configuration to read. `deploy()` is the
///      unit the tests call directly; `run()` only wraps it in a broadcast.
contract DeployCoindeskToken is Script {
    /// @notice Deploys the token. The caller of this function (the broadcaster under `run()`) receives the
    ///         whole supply.
    function deploy() public returns (CoindeskToken token) {
        token = new CoindeskToken();
    }

    /// @notice Entry point for `forge script`. The broadcasting account becomes the deployer and the holder of
    ///         the full supply.
    function run() external returns (CoindeskToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}

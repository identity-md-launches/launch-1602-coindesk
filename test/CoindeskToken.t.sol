// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoindeskToken} from "../src/CoindeskToken.sol";

/// @notice Stands in for the launch factory: deploys the token so that `msg.sender` in the constructor is this
///         contract, then moves the supply the way the factory does.
contract FactoryStub {
    CoindeskToken public token;

    function deploy() external returns (CoindeskToken) {
        token = new CoindeskToken();
        return token;
    }

    function deploy2(bytes32 salt) external returns (CoindeskToken) {
        token = new CoindeskToken{salt: salt}();
        return token;
    }

    function move(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract CoindeskTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether; // 1e9 * 1e18

    CoindeskToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new CoindeskToken();
    }

    // ----------------------------------------------------------------------------------------------------------
    // Metadata and supply
    // ----------------------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "Coindesk");
        assertEq(token.symbol(), "COINDESK");
        assertEq(token.decimals(), 18);
        assertEq(token.NAME(), "Coindesk");
        assertEq(token.SYMBOL(), "COINDESK");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** 18);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), deployer, EXPECTED_SUPPLY);
        vm.prank(deployer);
        new CoindeskToken();
    }

    function test_deployerIsMsgSenderNotTxOrigin() public {
        // The factory deploys the token from inside a contract call: the supply must go to that contract, not
        // to the EOA that started the transaction.
        FactoryStub factory = new FactoryStub();
        vm.prank(stranger, stranger);
        CoindeskToken deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), EXPECTED_SUPPLY);
        assertEq(deployed.balanceOf(stranger), 0);
        assertEq(deployed.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_deploysViaCreate2WithNoArguments() public {
        FactoryStub factory = new FactoryStub();
        bytes32 salt = bytes32(uint256(7));
        address predicted =
            vm.computeCreate2Address(salt, keccak256(type(CoindeskToken).creationCode), address(factory));
        CoindeskToken deployed = factory.deploy2(salt);
        assertEq(address(deployed), predicted);
        assertEq(deployed.balanceOf(address(factory)), EXPECTED_SUPPLY);
    }

    // ----------------------------------------------------------------------------------------------------------
    // Transfers: success
    // ----------------------------------------------------------------------------------------------------------

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, 1_000 ether);
        assertTrue(token.transfer(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferOfZeroSucceeds() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        assertTrue(token.transfer(alice, 5 ether));
        assertEq(token.balanceOf(alice), 5 ether);
    }

    function test_transferWholeBalanceLeavesZero() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, EXPECTED_SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), EXPECTED_SUPPLY);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Approval(alice, bob, 60 ether);
        assertTrue(token.approve(bob, 60 ether));
        assertEq(token.allowance(alice, bob), 60 ether);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, stranger, 40 ether));
        assertEq(token.balanceOf(stranger), 40 ether);
        assertEq(token.balanceOf(alice), 60 ether);
        assertEq(token.allowance(alice, bob), 20 ether);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, bob, 100 ether);
        assertEq(token.allowance(alice, bob), type(uint256).max);
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_approveOverwritesPreviousAllowance() public {
        vm.startPrank(alice);
        token.approve(bob, 10 ether);
        token.approve(bob, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(alice, bob), 3 ether);
    }

    // ----------------------------------------------------------------------------------------------------------
    // Transfers: failure
    // ----------------------------------------------------------------------------------------------------------

    function test_RevertWhen_transferExceedsBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 10 ether + 1)
        );
        token.transfer(bob, 10 ether + 1);
    }

    function test_RevertWhen_transferFromZeroBalance() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 1));
        token.transfer(bob, 1);
    }

    function test_RevertWhen_transferToZeroAddress() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
    }

    function test_RevertWhen_transferFromExceedsAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 100 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 10 ether, 11 ether)
        );
        token.transferFrom(alice, bob, 11 ether);
    }

    function test_RevertWhen_transferFromWithoutAllowance() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(deployer, bob, 1);
    }

    function test_RevertWhen_transferFromExceedsOwnerBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.approve(bob, 10 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 5 ether, 6 ether));
        token.transferFrom(alice, bob, 6 ether);
    }

    function test_RevertWhen_approveZeroSpender() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_RevertWhen_sendingEtherToToken() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    // ----------------------------------------------------------------------------------------------------------
    // Fixed supply and absence of privileged powers
    // ----------------------------------------------------------------------------------------------------------

    function test_noMintPathExists() public {
        string[6] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setMinter(address)",
            "initialize(address)"
        ];
        address[2] memory callers = [stranger, deployer];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], stranger, type(uint128).max);
            for (uint256 c; c < callers.length; ++c) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(data);
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(stranger), 0);
    }

    function test_noOwnerOrPrivilegedControls() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000 ether);

        string[14] memory signatures = [
            "owner()",
            "pause()",
            "unpause()",
            "blacklist(address)",
            "freeze(address)",
            "setBlacklist(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "setFee(uint256)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], alice, true);
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
        }

        // The deployer cannot pull from a holder without an allowance.
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);

        // And the holder is untouched and still free to move.
        assertEq(token.balanceOf(alice), 1_000 ether);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 500 ether));
        assertEq(token.balanceOf(bob), 500 ether);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            assertTrue(op != 0xF4, "DELEGATECALL");
            assertTrue(op != 0xF2, "CALLCODE");
            assertTrue(op != 0xFF, "SELFDESTRUCT");
        }
    }

    // ----------------------------------------------------------------------------------------------------------
    // Launch flows: everything moves exactly what it says
    // ----------------------------------------------------------------------------------------------------------

    function test_launchFlowsArriveWhole() public {
        FactoryStub factory = new FactoryStub();
        CoindeskToken launched = factory.deploy();
        address distributor = makeAddr("distributor");
        address claimant = makeAddr("claimant");
        address remainderTo = makeAddr("remainderTo");
        address poolManager = makeAddr("poolManager");

        uint256 swarm = EXPECTED_SUPPLY * 1_000 / 10_000; // 10%
        uint256 pool = EXPECTED_SUPPLY * 8_800 / 10_000; // 88%
        uint256 remainder = EXPECTED_SUPPLY - swarm - pool; // 2%

        assertTrue(factory.move(distributor, swarm));
        assertTrue(factory.move(poolManager, pool));
        assertTrue(factory.move(remainderTo, remainder));
        assertEq(launched.balanceOf(distributor), swarm, "swarm share short");
        assertEq(launched.balanceOf(poolManager), pool, "pool seed short");
        assertEq(launched.balanceOf(remainderTo), remainder, "remainder short");
        assertEq(launched.balanceOf(address(factory)), 0, "factory kept something");

        vm.prank(distributor);
        assertTrue(launched.transfer(claimant, swarm));
        assertEq(launched.balanceOf(claimant), swarm, "claim short");
        assertEq(launched.balanceOf(distributor), 0);
        assertEq(launched.totalSupply(), EXPECTED_SUPPLY, "supply changed");
    }

    // ----------------------------------------------------------------------------------------------------------
    // Fuzz: conservation
    // ----------------------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - amount);
        }
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 amount) public {
        amount = bound(amount, EXPECTED_SUPPLY + 1, type(uint256).max);
        vm.prank(deployer);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, EXPECTED_SUPPLY, amount)
        );
        token.transfer(alice, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, EXPECTED_SUPPLY);
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(deployer);
        token.approve(bob, allowance_);
        vm.prank(bob);
        if (amount > allowance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, allowance_, amount)
            );
            token.transferFrom(deployer, alice, amount);
        } else {
            assertTrue(token.transferFrom(deployer, alice, amount));
            assertEq(token.balanceOf(alice), amount);
            assertEq(token.allowance(deployer, bob), allowance_ - amount);
        }
    }
}

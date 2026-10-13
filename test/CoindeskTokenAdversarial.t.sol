// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoindeskToken} from "src/CoindeskToken.sol";

/// @notice Boundary cases and algebraic properties complementing the original token tests.
/// forge-config: default.fuzz.runs = 1000
contract CoindeskTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    CoindeskToken internal token;
    address internal deployer = makeAddr("adversarial deployer");
    address internal holder = makeAddr("adversarial holder");
    address internal spender = makeAddr("adversarial spender");
    address internal recipient = makeAddr("adversarial recipient");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new CoindeskToken();
    }

    function test_constructorEmitsExactlyOneMintLog() public {
        vm.recordLogs();
        vm.prank(deployer);
        CoindeskToken fresh = new CoindeskToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        assertEq(logs.length, 1, "constructor must mint once");
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(deployer))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
        assertEq(fresh.balanceOf(deployer), SUPPLY);
        assertEq(fresh.balanceOf(address(0)), 0);
        assertEq(fresh.balanceOf(address(fresh)), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_oneWeiCanMakeAnExactRoundTrip() public {
        _transfer(deployer, holder, 1);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        _transfer(holder, deployer, 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransfersEmitEventsWithoutMovingValue() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        _transfer(holder, recipient, 0);

        // A zero delegated transfer needs neither tokens nor a positive allowance.
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(holder, recipient, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 0));
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferFromSpendsFiniteAllowanceWithoutChangingBalance() public {
        _approve(deployer, spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, deployer, 1);
    }

    function test_selfTransferCannotBypassTheBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY + 1);

        _approve(deployer, spender, SUPPLY + 1);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, deployer, SUPPLY + 1);
        assertEq(token.allowance(deployer, spender), SUPPLY + 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        _approve(deployer, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, SUPPLY));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_revocationOfInfiniteAllowanceTakesEffectImmediately() public {
        _approve(deployer, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max);

        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        _approve(deployer, spender, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(recipient), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_finiteAllowanceCannotBeSpentTwice() public {
        _approve(deployer, spender, 2);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, recipient, 1));
        assertTrue(token.transferFrom(deployer, recipient, 1));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        token.transferFrom(deployer, recipient, 1);
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(recipient), 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 2);
    }

    function test_allowanceIsScopedToBothOwnerAndSpender() public {
        _transfer(deployer, holder, 10);
        _approve(deployer, spender, 10);
        _approve(holder, recipient, 7);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(holder, spender, 1);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, recipient, 0, 1));
        vm.prank(recipient);
        token.transferFrom(deployer, recipient, 1);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, spender, 3));
        assertEq(token.allowance(deployer, spender), 7);
        assertEq(token.allowance(holder, recipient), 7);
        assertEq(token.allowance(spender, deployer), 0);
        assertEq(token.balanceOf(holder), 10);
        assertEq(token.balanceOf(spender), 3);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_approvalDoesNotReserveOrMintTokens() public {
        _approve(deployer, spender, type(uint256).max);
        _approve(holder, spender, type(uint256).max);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);

        _transfer(deployer, holder, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroAmountsStillRejectZeroRecipientAndSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(holder);
        token.transfer(address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(holder, address(0), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(holder);
        token.approve(address(0), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(token.allowance(holder, address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_invalidRecipientRollsBackAllowanceAndLeavesItSpendable() public {
        _approve(deployer, spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), SUPPLY);
        assertEq(token.allowance(deployer, spender), SUPPLY);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, SUPPLY));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(recipient), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
    }

    function test_insufficientBalanceRollsBackAllowanceAndLeavesItSpendable() public {
        _transfer(deployer, holder, 1);
        _approve(holder, spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, 1, 2));
        vm.prank(spender);
        token.transferFrom(holder, recipient, 2);
        assertEq(token.allowance(holder, spender), 2);
        assertEq(token.balanceOf(holder), 1);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(holder, recipient, 1));
        assertEq(token.allowance(holder, spender), 1);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(recipient), 1);
    }

    function test_uint256MaxCannotBeTransferredEvenWithInfiniteAllowance() public {
        uint256 maximum = type(uint256).max;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, maximum)
        );
        vm.prank(deployer);
        token.transfer(recipient, maximum);
        _approve(deployer, spender, maximum);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, maximum)
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, maximum);
        assertEq(token.allowance(deployer, spender), maximum);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_txOriginCannotAuthorizeSpendingOrApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, spender, 0, 1));
        vm.prank(spender, deployer);
        token.transfer(recipient, 1);

        vm.prank(spender, deployer);
        assertTrue(token.approve(recipient, SUPPLY));
        assertEq(token.allowance(spender, recipient), SUPPLY);
        assertEq(token.allowance(deployer, recipient), 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, recipient, 0, 1));
        vm.prank(recipient, deployer);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
    }

    function test_nonpayableApprovalRejectsEtherAndDoesNotSetAllowance() public {
        vm.deal(holder, 1 ether);
        vm.prank(holder);
        (bool ok,) = address(token).call{value: 1 ether}(abi.encodeCall(token.approve, (spender, SUPPLY)));
        assertFalse(ok);
        assertEq(token.allowance(holder, spender), 0);
        assertEq(address(token).balance, 0);
        assertEq(holder.balance, 1 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_tokenContractCanReceiveTokensWithoutBurningSupply() public {
        _transfer(deployer, address(token), 1);
        _approve(deployer, spender, SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_roundTripRestoresBothBalances(uint256 initialBalance, uint256 amount) public {
        initialBalance = bound(initialBalance, 0, SUPPLY);
        amount = bound(amount, 0, initialBalance);
        _transfer(deployer, holder, initialBalance);
        _transfer(holder, recipient, amount);
        assertEq(token.balanceOf(recipient), amount, "outbound transfer arrived short");
        _transfer(recipient, holder, amount);
        assertEq(token.balanceOf(holder), initialBalance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - initialBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_splitSpendingMatchesOneTransfer(uint256 first, uint256 second, uint256 approved, bool infinite)
        public
    {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        approved = infinite ? type(uint256).max : bound(approved, first + second, type(uint256).max - 1);
        vm.prank(deployer);
        CoindeskToken single = new CoindeskToken();
        _approve(deployer, spender, approved);
        vm.prank(deployer);
        assertTrue(single.approve(spender, approved));

        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, recipient, first));
        assertTrue(token.transferFrom(deployer, recipient, second));
        assertTrue(single.transferFrom(deployer, recipient, first + second));
        vm.stopPrank();

        assertEq(token.balanceOf(deployer), single.balanceOf(deployer));
        assertEq(token.balanceOf(recipient), single.balanceOf(recipient));
        assertEq(token.balanceOf(recipient), first + second, "splitting must not introduce fees or rounding");
        assertEq(token.allowance(deployer, spender), single.allowance(deployer, spender));
        assertEq(token.allowance(deployer, spender), infinite ? approved : approved - first - second);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }

    function testFuzz_failedDelegatedTransferIsAtomic(uint256 balance, uint256 amount, uint256 approved, bool infinite)
        public
    {
        balance = bound(balance, 0, SUPPLY);
        amount = bound(amount, balance + 1, type(uint256).max - 1);
        approved = infinite ? type(uint256).max : bound(approved, amount, type(uint256).max - 1);
        _transfer(deployer, holder, balance);
        _approve(holder, spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, balance, amount));
        vm.prank(spender);
        token.transferFrom(holder, recipient, amount);
        assertEq(token.allowance(holder, spender), approved, "revert consumed allowance");
        assertEq(token.balanceOf(holder), balance);
        assertEq(token.balanceOf(deployer), SUPPLY - balance);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_replacingApprovalNeverAddsToOldApproval(uint256 oldApproval, uint256 replacement) public {
        _approve(deployer, spender, oldApproval);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, replacement);
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement);
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement, "repeating approval must be idempotent");
        _approve(deployer, spender, 0);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, recipient, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_loweringApprovalInvalidatesTheOldLimit(uint256 oldApproval, uint256 replacement) public {
        oldApproval = bound(oldApproval, 1, SUPPLY);
        replacement = bound(replacement, 0, oldApproval - 1);
        _approve(deployer, spender, oldApproval);
        _approve(deployer, spender, replacement);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, replacement, replacement + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(deployer, recipient, replacement + 1);
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(recipient), 0);

        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, recipient, replacement));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - replacement);
        assertEq(token.balanceOf(recipient), replacement);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
    }

    function _approve(address owner, address delegate, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(delegate, amount));
    }
}

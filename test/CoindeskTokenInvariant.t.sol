// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {CoindeskToken} from "src/CoindeskToken.sol";

/// @notice Drives the actual token using only its public ERC-20 interface.
/// @dev The actor set is closed: all destinations are actors or the token itself. The token is
///      a tracked recipient, never impersonated as a sender. No deal/store/mint cheatcodes are used.
contract CoindeskTokenHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 ether;
    uint256 public constant ACTOR_COUNT = 4;

    CoindeskToken public immutable token;
    address[4] public actors;

    // Expected state is seeded from the specification and updated from requested operations.
    // Never copy a token balance/allowance into the model: doing so could bless incorrect accounting.
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    constructor() {
        actors[0] = address(this); // The contract deployer is also an ordinary holder and spender.
        actors[1] = makeAddr("invariant alice");
        actors[2] = makeAddr("invariant bob");
        actors[3] = makeAddr("invariant carol");
        token = new CoindeskToken();
        ghostBalance[address(this)] = SUPPLY;

        for (uint256 i = 1; i < ACTOR_COUNT; ++i) {
            _transfer(address(this), actors[i], SUPPLY / ACTOR_COUNT);
        }
        // Start with usable finite and infinite approvals, so delegated transfers are reachable
        // immediately. Later transfers consume these; approvals and revocations change them independently.
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            _approve(actors[i], actors[(i + 1) % ACTOR_COUNT], SUPPLY / ACTOR_COUNT);
            _approve(actors[i], actors[(i + 2) % ACTOR_COUNT], type(uint256).max);
        }
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _recipient(toSeed), _amount(amountSeed, ghostBalance[from]));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        if (mode % 4 == 0) amount = 0;
        else if (mode % 4 == 1) amount = type(uint256).max;
        else if (mode % 4 == 2) amount = type(uint256).max - 1;
        else amount = amountSeed; // Includes approvals larger than the supply, with no overflow-prone cap.
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _recipient(toSeed);
        uint256 allowed = ghostAllowance[owner][spender];
        uint256 limit = ghostBalance[owner] < allowed ? ghostBalance[owner] : allowed;
        uint256 amount = _amount(amountSeed, limit);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        if (allowed != type(uint256).max) ghostAllowance[owner][spender] -= amount;
        _moveInModel(owner, to, amount);
    }

    function selfTransfer(uint256 actorSeed, uint256 amountSeed) external {
        address actor = _actor(actorSeed);
        _transfer(actor, actor, _amount(amountSeed, ghostBalance[actor]));
    }

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        uint256 balance = ghostBalance[from];
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount));
        vm.prank(from);
        token.transfer(_recipient(toSeed), amount);
        // The ghost ledger is unchanged. The invariants must still agree with it after this revert.
    }

    function transferFromAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed)
        external
    {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Keep both the balance and the allowance sufficient for zero, but exceed only the
        // allowance whenever the holder has tokens. This catches off-by-one checks at approval zero.
        uint256 balance = ghostBalance[owner];
        uint256 allowed = balance == 0 ? 0 : bound(amountSeed, 0, balance - 1);
        _approve(owner, spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, _recipient(toSeed), allowed + 1);
    }

    function transferFromAboveBalance(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 balance = ghostBalance[owner];
        uint256 amount = balance + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount));
        vm.prank(spender);
        token.transferFrom(owner, _recipient(toSeed), amount);
        // In particular, a failed transfer must roll back the finite allowance decrement.
    }

    function transferToZero(uint256 ownerSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        uint256 amount = _amount(amountSeed, ghostBalance[owner]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(owner);
        token.transfer(address(0), amount);
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool infinite) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        uint256 amount = _amount(amountSeed, ghostBalance[owner]);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function revokeAndAttemptSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, _recipient(toSeed), 1);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(_actor(ownerSeed));
        token.approve(address(0), amount);
    }

    /// @dev Called by afterInvariant, not targeted by the random runner. Every spendable holder
    ///      must remain able to move its entire balance after any sequence, regardless of approvals.
    function moveAllActorBalances() external {
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            _transfer(actors[i], actors[(i + 1) % ACTOR_COUNT], ghostBalance[actors[i]]);
        }
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % ACTOR_COUNT];
    }

    function _recipient(uint256 seed) internal view returns (address) {
        uint256 index = seed % (ACTOR_COUNT + 1);
        return index == ACTOR_COUNT ? address(token) : actors[index];
    }

    /// @dev Explicitly bias valid calls toward zero, one base unit and the entire available amount.
    function _amount(uint256 seed, uint256 limit) internal pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return limit == 0 ? 0 : 1;
        if (seed % 4 == 2) return limit;
        return _bound(seed, 0, limit);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _moveInModel(from, to, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        ghostAllowance[owner][spender] = amount;
    }

    function _moveInModel(address from, address to, uint256 amount) internal {
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
    }
}

/// @notice Random call sequences must preserve fixed supply, exact balances and spending authority.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CoindeskTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    CoindeskTokenHandler internal handler;
    CoindeskToken internal token;

    function setUp() public {
        handler = new CoindeskTokenHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.approve.selector;
        selectors[2] = handler.transferFrom.selector;
        selectors[3] = handler.selfTransfer.selector;
        selectors[4] = handler.transferAboveBalance.selector;
        selectors[5] = handler.transferFromAboveAllowance.selector;
        selectors[6] = handler.transferFromAboveBalance.selector;
        selectors[7] = handler.transferToZero.selector;
        selectors[8] = handler.transferFromToZero.selector;
        selectors[9] = handler.revokeAndAttemptSpend.selector;
        selectors[10] = handler.approveZeroSpender.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndMetadataStayFixed() public view {
        assertEq(token.totalSupply(), SUPPLY, "supply changed after deployment");
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.name(), "Coindesk");
        assertEq(token.symbol(), "COINDESK");
        assertEq(token.decimals(), 18);
    }

    function invariant_balancesMatchLedgerAndConserveSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.ghostBalance(actor), "actor balance differs from intended transfers");
            sum += balance;
        }
        uint256 heldByToken = token.balanceOf(address(token));
        assertEq(heldByToken, handler.ghostBalance(address(token)), "tokens sent to the token were lost");
        assertEq(sum + heldByToken, SUPPLY, "tracked balances do not conserve the constructor mint");
        assertEq(token.balanceOf(address(0)), 0, "tokens reached the zero address");
        assertEq(token.balanceOf(address(this)), 0, "tokens escaped the tracked recipient set");
    }

    function invariant_allowancesMatchApprovalAndSpendingHistory() public view {
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address owner = handler.actors(i);
            for (uint256 j; j < handler.ACTOR_COUNT(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(owner, spender),
                    handler.ghostAllowance(owner, spender),
                    "allowance changed without approval or successful authorized spending"
                );
            }
            assertEq(token.allowance(owner, address(0)), 0, "zero spender gained an allowance");
            assertEq(token.allowance(address(0), owner), 0, "zero address granted an allowance");
        }
    }

    function afterInvariant() public {
        handler.moveAllActorBalances();
        _checkAll();
    }

    /// @dev Pins nonzero paths as a reproducible sequence alongside the random campaign.
    function test_handlerSequenceCoversNonzeroSpendingRevocationAndFailures() public {
        address owner = handler.actors(0);
        address delegate = handler.actors(1);
        address receiver = handler.actors(2);

        handler.transferFrom(0, 1, 2, 1); // One unit, using a finite approval seeded in the constructor.
        assertEq(token.balanceOf(receiver), SUPPLY / 4 + 1);
        assertEq(token.allowance(owner, delegate), SUPPLY / 4 - 1);
        _checkAll();

        handler.approve(0, 1, 0, 1); // Infinite approval, then an entire-balance self-transfer.
        handler.transferFrom(0, 1, 0, 2);
        assertEq(token.allowance(owner, delegate), type(uint256).max);
        _checkAll();

        handler.revokeAndAttemptSpend(0, 1, 2);
        handler.transferFromAboveBalance(0, 1, 2, false);
        handler.transferFromAboveAllowance(0, 1, 2, 1);
        handler.transferFromToZero(0, 1, 2, false);
        handler.transferToZero(0, 1);
        handler.transferAboveBalance(0, 2, type(uint256).max);
        handler.approveZeroSpender(0, type(uint256).max);
        _checkAll();

        handler.selfTransfer(0, 2);
        handler.transfer(0, 4, 1); // The token contract is included in conservation accounting.
        assertEq(token.balanceOf(address(token)), 1);
        afterInvariant();
    }

    function _checkAll() internal view {
        invariant_supplyAndMetadataStayFixed();
        invariant_balancesMatchLedgerAndConserveSupply();
        invariant_allowancesMatchApprovalAndSpendingHistory();
    }
}

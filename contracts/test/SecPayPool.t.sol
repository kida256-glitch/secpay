// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {SecPayPool} from "../src/SecPayPool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ReenterToken is ERC20 {
    constructor() ERC20("Callback", "CALL") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (to.code.length > 0) to.call(abi.encodeWithSignature("onTokenReceived()"));
        return ok;
    }
}

contract ReenteringEmployee {
    SecPayPool immutable secpay;
    uint256 immutable poolId;
    bool public reentered;
    constructor(SecPayPool secpay_, uint256 poolId_) { secpay = secpay_; poolId = poolId_; }
    function attack() external { secpay.withdraw(poolId); }
    function onTokenReceived() external { (reentered,) = address(secpay).call(abi.encodeCall(SecPayPool.withdraw, (poolId))); }
}

contract SecPayPoolTest is Test {
    uint256 constant SALARY = 3_000_000_000; // 3,000 mUSDC in six-decimal units
    address employer = makeAddr("employer");
    address employee = makeAddr("employee");
    address secondEmployee = makeAddr("secondEmployee");
    MockUSDC usdc;
    SecPayPool secpay;

    function setUp() public {
        usdc = new MockUSDC(); secpay = new SecPayPool(usdc);
        vm.startPrank(employer); usdc.faucet(); usdc.approve(address(secpay), type(uint256).max); vm.stopPrank();
    }

    function _fundAndStart(uint256 salary) internal returns (uint256 id) {
        vm.startPrank(employer);
        id = secpay.createPool(); secpay.addEmployee(id, employee, salary); secpay.deposit(id, salary); secpay.startPayPeriod(id);
        vm.stopPrank();
    }

    function testCreateAddDepositAndStart() public {
        uint256 id = _fundAndStart(SALARY);
        SecPayPool.Pool memory p = secpay.getPoolInfo(id);
        assertEq(p.poolBalance, SALARY); assertTrue(p.active); assertEq(p.payPeriodEnd - p.payPeriodStart, 30 days);
    }

    function testAccruesAtStoredRateAfterSeconds() public {
        uint256 id = _fundAndStart(SALARY); vm.warp(block.timestamp + 3600);
        (, SecPayPool.Employee[] memory data,) = secpay.getEmployees(id);
        assertEq(secpay.accruedBalance(id, employee), data[0].ratePerSecond * 3600 / 1e18);
    }

    function testWithdrawTransfersAndResetsAccrual() public {
        uint256 id = _fundAndStart(SALARY); vm.warp(block.timestamp + 1 days);
        uint256 owing = secpay.accruedBalance(id, employee); vm.prank(employee); secpay.withdraw(id);
        assertEq(usdc.balanceOf(employee), owing); assertEq(secpay.accruedBalance(id, employee), 0);
    }

    function testSequentialWithdrawalsNeverExceedSalaryAndFullMonthIsExact() public {
        uint256 id = _fundAndStart(SALARY); vm.warp(block.timestamp + 10 days);
        vm.prank(employee); secpay.withdraw(id); vm.warp(block.timestamp + 20 days);
        vm.prank(employee); secpay.withdraw(id);
        assertEq(usdc.balanceOf(employee), SALARY);
    }

    function testRemoveFreezesAccrualAndRemainsWithdrawable() public {
        uint256 id = _fundAndStart(SALARY); vm.warp(block.timestamp + 5 days);
        vm.prank(employer); secpay.removeEmployee(id, employee); uint256 frozen = secpay.accruedBalance(id, employee);
        vm.warp(block.timestamp + 10 days); assertEq(secpay.accruedBalance(id, employee), frozen);
        vm.prank(employee); secpay.withdraw(id); assertEq(usdc.balanceOf(employee), frozen);
    }

    function testSalaryUpdateSettlesOldRateThenUsesNewRate() public {
        uint256 id = _fundAndStart(SALARY); vm.warp(block.timestamp + 5 days);
        uint256 first = secpay.accruedBalance(id, employee);
        vm.prank(employer); secpay.deposit(id, SALARY);
        vm.prank(employer); secpay.updateSalary(id, employee, SALARY * 2);
        vm.warp(block.timestamp + 5 days); uint256 second = secpay.accruedBalance(id, employee);
        assertGt(second, first); assertEq(second - first, (SALARY * 2 * 1e18 / 30 days) * 5 days / 1e18);
    }

    function testPauseFreezesAccrual() public {
        uint256 id = _fundAndStart(SALARY); vm.warp(block.timestamp + 2 days);
        vm.prank(employer); secpay.pausePool(id); uint256 beforePause = secpay.accruedBalance(id, employee);
        vm.warp(block.timestamp + 3 days); assertEq(secpay.accruedBalance(id, employee), beforePause);
        vm.prank(employer); secpay.unpausePool(id); vm.warp(block.timestamp + 1 days);
        assertGt(secpay.accruedBalance(id, employee), beforePause);
    }

    function testOnlyEmployerAndSurplusSafety() public {
        uint256 id = _fundAndStart(SALARY); vm.prank(employee); vm.expectRevert(SecPayPool.NotEmployer.selector); secpay.deposit(id, 1);
        vm.prank(employer); vm.expectRevert(SecPayPool.NothingToWithdrawAsSurplus.selector); secpay.withdrawSurplus(id);
        vm.prank(employer); secpay.deposit(id, 1_000_000); vm.prank(employer); secpay.withdrawSurplus(id);
        assertEq(usdc.balanceOf(address(secpay)), SALARY);
    }

    function testReentrantWithdrawAttemptFails() public {
        ReenterToken token = new ReenterToken(); SecPayPool guarded = new SecPayPool(token);
        uint256 id;
        vm.startPrank(employer);
        token.mint(employer, SALARY); token.approve(address(guarded), SALARY);
        id = guarded.createPool();
        ReenteringEmployee attacker = new ReenteringEmployee(guarded, id);
        guarded.addEmployee(id, address(attacker), SALARY); guarded.deposit(id, SALARY); guarded.startPayPeriod(id);
        vm.stopPrank();
        vm.warp(block.timestamp + 1 days); attacker.attack();
        assertFalse(attacker.reentered());
    }

    function testFuzzAccrualBounded(uint96 rawSalary, uint32 jump) public {
        uint256 salary = bound(uint256(rawSalary), 1_000_000, 10_000_000_000);
        uint256 id = _fundAndStart(salary); vm.warp(block.timestamp + bound(uint256(jump), 0, 30 days));
        assertLe(secpay.accruedBalance(id, employee), salary);
    }
}

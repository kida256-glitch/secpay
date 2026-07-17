// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

/// @title SecPayPool
/// @notice Lazy, ERC-20 payroll streams. Token units are never converted to 18 decimals.
contract SecPayPool is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    uint256 public constant PAY_PERIOD = 30 days;
    uint256 private constant RATE_SCALE = 1e18;

    IERC20 public immutable paymentToken;
    uint256 public poolCount;

    struct Pool {
        address employer;
        IERC20 token;
        uint256 poolBalance;
        uint256 payPeriodStart;
        uint256 payPeriodEnd;
        uint256 pausedAt;
        uint256 totalPausedDuration;
        uint256 totalMonthlyObligations;
        uint256 reservedBalance;
        bool active;
        bool paused;
    }

    struct Employee {
        uint256 monthlySalary;
        uint256 ratePerSecond; // token units * 1e18 / second
        uint256 lastWithdrawTime; // virtual (pause-adjusted) timestamp
        uint256 accruedStored;
        uint256 streamEnd; // virtual timestamp; zero while active
        uint256 reserved; // maximum remaining amount this employee can claim
        bool exists;
        bool active;
    }

    mapping(uint256 => Pool) private pools;
    mapping(uint256 => mapping(address => Employee)) private employees;
    mapping(uint256 => address[]) private poolEmployees;
    mapping(address => uint256[]) private employeePools;
    mapping(address => uint256[]) private employerPools;

    error ZeroAddress(); error ZeroAmount(); error PoolNotFound(); error NotEmployer();
    error EmployeeExists(); error EmployeeMissing(); error PoolAlreadyStarted(); error PoolNotActive();
    error PoolPausedError(); error PoolNotPaused(); error InsufficientFunding(uint256 available, uint256 required);
    error NothingToWithdraw(); error NothingToWithdrawAsSurplus(); error StreamNotStarted();

    event PoolCreated(uint256 indexed poolId, address indexed employer, address indexed token);
    event EmployeeAdded(uint256 indexed poolId, address indexed employee, uint256 monthlySalary);
    event EmployeeRemoved(uint256 indexed poolId, address indexed employee, uint256 accrued);
    event SalaryUpdated(uint256 indexed poolId, address indexed employee, uint256 oldSalary, uint256 newSalary);
    event Deposited(uint256 indexed poolId, address indexed employer, uint256 amount);
    event PayPeriodStarted(uint256 indexed poolId, uint256 start, uint256 end);
    event Withdrawn(uint256 indexed poolId, address indexed employee, uint256 amount);
    event PoolPaused(uint256 indexed poolId, uint256 at);
    event PoolUnpaused(uint256 indexed poolId, uint256 at, uint256 pausedDuration);
    event SurplusWithdrawn(uint256 indexed poolId, address indexed employer, uint256 amount);

    constructor(IERC20 token_) Ownable(msg.sender) { if (address(token_) == address(0)) revert ZeroAddress(); paymentToken = token_; }

    modifier onlyEmployer(uint256 poolId) {
        if (pools[poolId].employer == address(0)) revert PoolNotFound();
        if (pools[poolId].employer != msg.sender) revert NotEmployer();
        _;
    }

    function createPool() external returns (uint256 poolId) {
        poolId = ++poolCount;
        Pool storage pool = pools[poolId];
        pool.employer = msg.sender;
        pool.token = paymentToken;
        employerPools[msg.sender].push(poolId);
        emit PoolCreated(poolId, msg.sender, address(paymentToken));
    }

    function addEmployee(uint256 poolId, address employee, uint256 monthlySalary) external onlyEmployer(poolId) {
        if (employee == address(0)) revert ZeroAddress(); if (monthlySalary == 0) revert ZeroAmount();
        Pool storage pool = pools[poolId];
        if (pool.paused) revert PoolPausedError();
        Employee storage e = employees[poolId][employee];
        if (e.exists) revert EmployeeExists();
        e.monthlySalary = monthlySalary;
        e.ratePerSecond = monthlySalary * RATE_SCALE / PAY_PERIOD;
        if (pool.active) {
            uint256 remaining = _effectiveNow(pool) >= pool.payPeriodEnd ? 0 : pool.payPeriodEnd - _effectiveNow(pool);
            e.reserved = _ceilDiv(e.ratePerSecond * remaining, RATE_SCALE);
            uint256 required = pool.reservedBalance + e.reserved;
            if (pool.poolBalance < required) revert InsufficientFunding(pool.poolBalance, required);
            pool.reservedBalance = required;
            e.lastWithdrawTime = _effectiveNow(pool);
        } else {
            e.reserved = monthlySalary;
            pool.reservedBalance += monthlySalary;
        }
        e.exists = true; e.active = true;
        pool.totalMonthlyObligations += monthlySalary;
        poolEmployees[poolId].push(employee);
        employeePools[employee].push(poolId);
        emit EmployeeAdded(poolId, employee, monthlySalary);
    }

    function removeEmployee(uint256 poolId, address employee) external onlyEmployer(poolId) {
        Pool storage pool = pools[poolId]; Employee storage e = employees[poolId][employee];
        if (!e.exists || !e.active) revert EmployeeMissing();
        if (pool.active) _settle(pool, e);
        uint256 priorReserved = e.reserved;
        e.reserved = e.accruedStored;
        pool.reservedBalance -= priorReserved - e.reserved;
        pool.totalMonthlyObligations -= e.monthlySalary;
        e.active = false; e.streamEnd = _effectiveNow(pool);
        emit EmployeeRemoved(poolId, employee, e.accruedStored);
    }

    function updateSalary(uint256 poolId, address employee, uint256 newMonthlySalary) external onlyEmployer(poolId) {
        if (newMonthlySalary == 0) revert ZeroAmount();
        Pool storage pool = pools[poolId]; Employee storage e = employees[poolId][employee];
        if (!e.exists || !e.active) revert EmployeeMissing();
        uint256 old = e.monthlySalary;
        if (!pool.active) {
            pool.reservedBalance = pool.reservedBalance - e.reserved + newMonthlySalary;
            e.reserved = newMonthlySalary;
        } else {
            if (pool.paused) revert PoolPausedError();
            _settle(pool, e);
            uint256 virtualNow = _effectiveNow(pool);
            uint256 remaining = virtualNow >= pool.payPeriodEnd ? 0 : pool.payPeriodEnd - virtualNow;
            uint256 newRate = newMonthlySalary * RATE_SCALE / PAY_PERIOD;
            uint256 futureMax = _ceilDiv(newRate * remaining, RATE_SCALE);
            uint256 newReserved = e.accruedStored + futureMax;
            uint256 candidate = pool.reservedBalance - e.reserved + newReserved;
            if (pool.poolBalance < candidate) revert InsufficientFunding(pool.poolBalance, candidate);
            pool.reservedBalance = candidate; e.reserved = newReserved;
        }
        pool.totalMonthlyObligations = pool.totalMonthlyObligations - old + newMonthlySalary;
        e.monthlySalary = newMonthlySalary; e.ratePerSecond = newMonthlySalary * RATE_SCALE / PAY_PERIOD;
        e.lastWithdrawTime = _effectiveNow(pool);
        emit SalaryUpdated(poolId, employee, old, newMonthlySalary);
    }

    function deposit(uint256 poolId, uint256 amount) external onlyEmployer(poolId) {
        if (amount == 0) revert ZeroAmount(); Pool storage pool = pools[poolId];
        pool.token.safeTransferFrom(msg.sender, address(this), amount); pool.poolBalance += amount;
        emit Deposited(poolId, msg.sender, amount);
    }

    function startPayPeriod(uint256 poolId) external onlyEmployer(poolId) {
        Pool storage pool = pools[poolId]; if (pool.active) revert PoolAlreadyStarted();
        if (pool.poolBalance < pool.reservedBalance) revert InsufficientFunding(pool.poolBalance, pool.reservedBalance);
        pool.active = true; pool.payPeriodStart = block.timestamp; pool.payPeriodEnd = block.timestamp + PAY_PERIOD;
        address[] storage list = poolEmployees[poolId];
        for (uint256 i; i < list.length; ++i) {
            Employee storage e = employees[poolId][list[i]];
            if (e.active) { e.lastWithdrawTime = block.timestamp; e.streamEnd = 0; }
        }
        emit PayPeriodStarted(poolId, pool.payPeriodStart, pool.payPeriodEnd);
    }

    function pausePool(uint256 poolId) external onlyEmployer(poolId) {
        Pool storage pool = pools[poolId]; if (!pool.active) revert PoolNotActive(); if (pool.paused) revert PoolPausedError();
        pool.paused = true; pool.pausedAt = block.timestamp; emit PoolPaused(poolId, block.timestamp);
    }

    function unpausePool(uint256 poolId) external onlyEmployer(poolId) {
        Pool storage pool = pools[poolId]; if (!pool.paused) revert PoolNotPaused();
        uint256 duration = block.timestamp - pool.pausedAt; pool.totalPausedDuration += duration; pool.pausedAt = 0; pool.paused = false;
        emit PoolUnpaused(poolId, block.timestamp, duration);
    }

    function withdraw(uint256 poolId) external nonReentrant {
        Pool storage pool = pools[poolId]; if (!pool.active) revert StreamNotStarted();
        Employee storage e = employees[poolId][msg.sender]; if (!e.exists) revert EmployeeMissing();
        _settle(pool, e); uint256 amount = e.accruedStored; if (amount == 0) revert NothingToWithdraw();
        e.accruedStored = 0; e.reserved -= amount; pool.reservedBalance -= amount; pool.poolBalance -= amount;
        pool.token.safeTransfer(msg.sender, amount); emit Withdrawn(poolId, msg.sender, amount);
    }

    function withdrawSurplus(uint256 poolId) external onlyEmployer(poolId) nonReentrant {
        Pool storage pool = pools[poolId]; uint256 amount = pool.poolBalance - pool.reservedBalance;
        if (amount == 0) revert NothingToWithdrawAsSurplus(); pool.poolBalance -= amount;
        pool.token.safeTransfer(msg.sender, amount); emit SurplusWithdrawn(poolId, msg.sender, amount);
    }

    function accruedBalance(uint256 poolId, address employee) public view returns (uint256) {
        Pool storage pool = pools[poolId]; Employee storage e = employees[poolId][employee]; if (!e.exists) return 0;
        return _accrued(pool, e);
    }

    function getPoolInfo(uint256 poolId) external view returns (Pool memory) { if (pools[poolId].employer == address(0)) revert PoolNotFound(); return pools[poolId]; }
    function getEmployees(uint256 poolId) external view returns (address[] memory addresses, Employee[] memory data, uint256[] memory accrued) {
        if (pools[poolId].employer == address(0)) revert PoolNotFound(); address[] storage list = poolEmployees[poolId];
        addresses = new address[](list.length); data = new Employee[](list.length); accrued = new uint256[](list.length);
        for (uint256 i; i < list.length; ++i) { addresses[i] = list[i]; data[i] = employees[poolId][list[i]]; accrued[i] = _accrued(pools[poolId], data[i]); }
    }
    function getEmployeePools(address employee) external view returns (uint256[] memory) { return employeePools[employee]; }
    function getEmployerPools(address employer) external view returns (uint256[] memory) { return employerPools[employer]; }

    function _settle(Pool storage pool, Employee storage e) internal {
        uint256 total = _accrued(pool, e); e.accruedStored = total; e.lastWithdrawTime = _effectiveNow(pool);
    }
    function _accrued(Pool storage pool, Employee memory e) internal view returns (uint256) {
        if (!pool.active || e.lastWithdrawTime == 0) return e.accruedStored;
        uint256 until = e.streamEnd == 0 ? _effectiveNow(pool) : e.streamEnd;
        if (until <= e.lastWithdrawTime) return e.accruedStored;
        // At an unpaused natural period end every remaining reserved token is
        // owed to this employee. Returning the reservation (rather than a
        // second rounded interval) preserves the division remainder across
        // any number of earlier withdrawals.
        if (until == pool.payPeriodEnd) return e.reserved;
        uint256 streamed = e.ratePerSecond * (until - e.lastWithdrawTime) / RATE_SCALE;
        uint256 result = e.accruedStored + streamed;
        return result > e.reserved ? e.reserved : result;
    }
    function _effectiveNow(Pool storage pool) internal view returns (uint256) {
        if (!pool.active) return 0; uint256 raw = block.timestamp < pool.payPeriodEnd ? block.timestamp : pool.payPeriodEnd;
        uint256 paused = pool.totalPausedDuration; if (pool.paused && raw > pool.pausedAt) paused += raw - pool.pausedAt;
        return raw - paused;
    }
    function _ceilDiv(uint256 x, uint256 y) private pure returns (uint256) { return x == 0 ? 0 : (x - 1) / y + 1; }
}

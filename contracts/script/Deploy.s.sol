// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockUSDC} from "../src/MockUSDC.sol";
import {SecPayPool} from "../src/SecPayPool.sol";

contract Deploy is Script {
    function run() external returns (MockUSDC usdc, SecPayPool pool) {
        uint256 key = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(key);
        usdc = new MockUSDC();
        pool = new SecPayPool(usdc);
        vm.stopBroadcast();
        string memory deployment = "deployment";
        vm.serializeAddress(deployment, "mockUSDC", address(usdc));
        string memory json = vm.serializeAddress(deployment, "secPayPool", address(pool));
        vm.writeJson(json, "deployments/base-sepolia.json");
    }
}

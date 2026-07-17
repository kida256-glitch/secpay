// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from "forge-std/Script.sol";

/// @dev Writes deployment addresses supplied through env into frontend/src/contracts/deployment.ts.
contract SyncFrontend is Script {
    function run() external {
        string memory output = string.concat(
            "export const deployedAddresses = { secPayPool: '", vm.envString("SECPAY_POOL_ADDRESS"),
            "', mockUSDC: '", vm.envString("MOCK_USDC_ADDRESS"), "' } as const;\n"
        );
        vm.writeFile("../frontend/src/contracts/deployment.ts", output);
    }
}


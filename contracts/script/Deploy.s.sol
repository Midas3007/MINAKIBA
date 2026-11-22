// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {FundVault} from "../src/FundVault.sol";
import {MockUSDC} from "../test/MockUSDC.sol";

/// Deploys FundVault. Every setting comes from the environment so nothing is hard-coded here; values for MINAKIBA
/// are in config/fund.config.js.
///   OWNER, OPERATOR, MANAGER, FEE_RECIPIENT, TREASURY   addresses
///   FEE_BPS, MIN_DEPOSIT, MAX_PER_MEMBER, MAX_TOTAL      numbers (USDC amounts in 6-decimal units)
///   USDC                                                 the USDC address; leave unset on Base Sepolia to deploy a mock
contract Deploy is Script {
    function run() external returns (FundVault vault) {
        address usdc = vm.envOr("USDC", address(0));
        vm.startBroadcast();
        if (usdc == address(0)) {
            require(block.chainid == 84532, "USDC must be set outside Base Sepolia");
            usdc = address(new MockUSDC());
            console2.log("MockUSDC", usdc);
        }
        vault = new FundVault(
            usdc,
            vm.envAddress("OWNER"),
            vm.envAddress("OPERATOR"),
            vm.envAddress("MANAGER"),
            vm.envAddress("FEE_RECIPIENT"),
            vm.envAddress("TREASURY"),
            vm.envUint("FEE_BPS"),
            vm.envUint("MIN_DEPOSIT"),
            vm.envUint("MAX_PER_MEMBER"),
            vm.envUint("MAX_TOTAL")
        );
        vm.stopBroadcast();
        console2.log("FundVault", address(vault));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {safeconsole} from "forge-std/safeconsole.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Core} from "openzeppelin-foundry-upgrades/internal/Core.sol";

import {KtonDAOVaultV2} from "../src/staking/KtonDAOVaultV2.sol";

contract MigrateScript is Script {
    address vault = 0x652182C6aBc0bBE41b5702b05a26d109A405EAcA;

    function run() public {
        vm.startBroadcast();

        // new KtonDAOVaultV2();
        Core.upgradeProxyTo(vault, 0x8Dc2A9969252380f3a1725bfc6601E061cf2551f, "");

        vm.stopBroadcast();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import {safeconsole} from "forge-std/safeconsole.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";

import {KtonDAOV3, IVotes, TimelockControllerUpgradeable} from "../src/governance/KtonDAOV3.sol";
import {KtonTimelockController} from "../src/governance/KtonTimelockController.sol";

contract DeployGKTONScript is Script {
    address internal constant DEFAULT_KTON_TOKEN = 0x9F284E1337A815fe77D2Ff4aE46544645B20c5ff;
    // Reference: https://kton.degov.ai/ (Darwinia block 13_736_436, 2026-11-03).
    uint256 internal constant INITIAL_PROPOSAL_THRESHOLD = 20e18;
    uint32 internal constant INITIAL_VOTING_PERIOD = 7 days;
    uint256 internal constant TIMELOCK_DELAY = 1 days;

    function run() public returns (address gKton, KtonDAOV3 ktonDao, KtonTimelockController timelock) {
        require(block.chainid == 1, "Only Ethereum mainnet");
        address wrappedToken = vm.envOr("KTON_TOKEN", DEFAULT_KTON_TOKEN);
        require(wrappedToken != address(0), "KTON_TOKEN is zero");

        vm.startBroadcast();
        (, address deployer,) = vm.readCallers();

        // Deploy the freshly compiled GKTON artifact.
        gKton = deployCode("GKTON.sol:GovernanceKTON", abi.encode(wrappedToken));
        timelock = new KtonTimelockController(TIMELOCK_DELAY, new address[](0), new address[](0), deployer);

        address daoProxy = Upgrades.deployTransparentProxy(
            "KtonDAOV3.sol:KtonDAOV3",
            address(timelock),
            abi.encodeCall(
                KtonDAOV3.initialize,
                (
                    IVotes(gKton),
                    TimelockControllerUpgradeable(payable(address(timelock))),
                    0,
                    INITIAL_VOTING_PERIOD,
                    INITIAL_PROPOSAL_THRESHOLD,
                    "KtonDAO"
                )
            )
        );
        ktonDao = KtonDAOV3(payable(daoProxy));

        timelock.grantRole(timelock.PROPOSER_ROLE(), daoProxy);
        timelock.grantRole(timelock.CANCELLER_ROLE(), daoProxy);
        timelock.grantRole(timelock.EXECUTOR_ROLE(), daoProxy);
        timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        vm.stopBroadcast();

        safeconsole.log("Chain Id: ", block.chainid);
        safeconsole.log("KTON: ", wrappedToken);
        safeconsole.log("gKTON: ", gKton);
        safeconsole.log("KtonDAOV3: ", daoProxy);
        safeconsole.log("KtonDAOV3_Logic: ", Upgrades.getImplementationAddress(daoProxy));
        safeconsole.log("Timelock: ", address(timelock));
    }
}

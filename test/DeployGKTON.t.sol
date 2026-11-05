// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {DeployGKTONScript} from "../script/DeployGKTON.s.sol";
import {KtonDAOV3, IVotes} from "../src/governance/KtonDAOV3.sol";
import {KtonTimelockController} from "../src/governance/KtonTimelockController.sol";

interface IGKTON is IVotes {
    function underlying() external view returns (address);
    function depositFor(address account, uint256 value) external returns (bool);
}

contract MockKTON is ERC20 {
    constructor() ERC20("KTON", "KTON") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract GovernanceTarget {
    address public immutable timelock;
    uint256 public value;

    constructor(address timelock_) {
        timelock = timelock_;
    }

    function setValue(uint256 value_) external {
        require(msg.sender == timelock, "Only timelock");
        value = value_;
    }
}

contract DeployGKTONTest is Test {
    DeployGKTONScript internal deployScript;
    MockKTON internal underlying;

    function setUp() public {
        deployScript = new DeployGKTONScript();
        underlying = new MockKTON();
        vm.setEnv("KTON_TOKEN", vm.toString(address(underlying)));
    }

    function testDeployEthereumAndExecuteProposal() public {
        (address gKton, KtonDAOV3 dao, KtonTimelockController timelock) = _checkDeployment();

        vm.expectRevert(abi.encodeWithSelector(IGovernor.GovernorOnlyExecutor.selector, address(this)));
        dao.updateQuorum(4_000e18);
        assertEq(dao.quorum(), 3_000e18);

        uint256 amount = 3_001e18;
        underlying.mint(address(this), amount);
        underlying.approve(gKton, amount);
        IGKTON(gKton).depositFor(address(this), amount);
        IGKTON(gKton).delegate(address(this));
        vm.warp(block.timestamp + 1);

        GovernanceTarget target = new GovernanceTarget(address(timelock));
        address[] memory targets = new address[](2);
        targets[0] = address(target);
        targets[1] = address(dao);
        uint256[] memory values = new uint256[](2);
        bytes[] memory calldatas = new bytes[](2);
        calldatas[0] = abi.encodeCall(GovernanceTarget.setValue, (42));
        calldatas[1] = abi.encodeCall(KtonDAOV3.updateQuorum, (4_000e18));
        string memory description = "Set target value and update quorum";
        bytes32 descriptionHash = keccak256(bytes(description));

        uint256 proposalId = dao.propose(targets, values, calldatas, description);
        vm.warp(dao.proposalSnapshot(proposalId) + 1);
        dao.castVote(proposalId, 1);
        vm.warp(dao.proposalDeadline(proposalId) + 1);
        dao.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        dao.execute(targets, values, calldatas, descriptionHash);
        vm.warp(dao.proposalEta(proposalId));
        dao.execute(targets, values, calldatas, descriptionHash);
        assertEq(target.value(), 42);
        assertEq(dao.quorum(), 4_000e18);
        assertEq(dao.quorum(dao.proposalSnapshot(proposalId)), 3_000e18);
        assertEq(dao.quorum(dao.clock()), 4_000e18);
        assertEq(uint256(dao.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    function testFuzzRejectUnsupportedChain(uint64 chainId) public {
        vm.assume(chainId != 1);
        vm.chainId(chainId);
        vm.expectRevert("Only Ethereum mainnet");
        deployScript.run();
    }

    function _checkDeployment() internal returns (address gKton, KtonDAOV3 dao, KtonTimelockController timelock) {
        vm.chainId(1);
        (gKton, dao, timelock) = deployScript.run();
        assertEq(IGKTON(gKton).underlying(), address(underlying));
        assertEq(address(dao.token()), gKton);
        assertEq(dao.timelock(), address(timelock));
        assertEq(dao.name(), "KtonDAO");
        assertEq(dao.quorum(), 3_000e18);
        assertEq(dao.quorum(dao.clock()), 3_000e18);
        assertEq(dao.quorum(dao.clock() - 1), 0);
        assertEq(dao.proposalThreshold(), 20e18);
        assertEq(dao.votingPeriod(), 7 days);
        assertEq(dao.votingDelay(), 0);
        assertEq(uint256(dao.clock()), block.timestamp);
        assertEq(dao.CLOCK_MODE(), "mode=timestamp");
        assertEq(timelock.getMinDelay(), 1 days);

        bytes32[3] memory roles = [timelock.PROPOSER_ROLE(), timelock.CANCELLER_ROLE(), timelock.EXECUTOR_ROLE()];
        for (uint256 i; i < roles.length; ++i) {
            assertEq(timelock.getRoleMemberCount(roles[i]), 1);
            assertTrue(timelock.hasRole(roles[i], address(dao)));
        }
        assertEq(timelock.getRoleMemberCount(timelock.DEFAULT_ADMIN_ROLE()), 1);
        assertTrue(timelock.hasRole(timelock.DEFAULT_ADMIN_ROLE(), address(timelock)));

        bytes32 adminSlot = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
        address proxyAdmin = address(uint160(uint256(vm.load(address(dao), adminSlot))));
        assertEq(ProxyAdmin(proxyAdmin).owner(), address(timelock));
    }

    struct Proposal {
        uint256 id;
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
    }

    function testLowerQuorumDoesNotReviveDefeatedProposal() public {
        (address gKton, KtonDAOV3 dao,) = _checkDeployment();
        address minority = address(0xA11CE);
        address majority = address(0xB0B);
        _depositVotes(gKton, minority, 1_000e18);
        _depositVotes(gKton, majority, 4_000e18);
        vm.warp(block.timestamp + 1);

        GovernanceTarget target = new GovernanceTarget(dao.timelock());
        Proposal memory oldProposal = _proposeAndVote(
            dao, minority, address(target), abi.encodeCall(GovernanceTarget.setValue, (42)), "Minority proposal"
        );
        vm.warp(dao.proposalDeadline(oldProposal.id) + 1);
        assertEq(uint256(dao.state(oldProposal.id)), uint256(IGovernor.ProposalState.Defeated));
        assertEq(dao.quorum(dao.proposalSnapshot(oldProposal.id)), 3_000e18);

        _changeQuorum(dao, majority, 500e18);
        assertEq(dao.quorum(), 500e18);
        assertEq(dao.quorum(dao.clock()), 500e18);

        assertEq(dao.quorum(dao.proposalSnapshot(oldProposal.id)), 3_000e18);
        assertEq(uint256(dao.state(oldProposal.id)), uint256(IGovernor.ProposalState.Defeated));
        vm.expectRevert(
            abi.encodeWithSelector(
                IGovernor.GovernorUnexpectedProposalState.selector,
                oldProposal.id,
                IGovernor.ProposalState.Defeated,
                bytes32(uint256(1) << uint256(IGovernor.ProposalState.Succeeded))
            )
        );
        dao.queue(oldProposal.targets, oldProposal.values, oldProposal.calldatas, oldProposal.descriptionHash);
        assertEq(target.value(), 0);
    }

    function testRaiseQuorumKeepsQueuedProposalExecutable() public {
        (address gKton, KtonDAOV3 dao,) = _checkDeployment();
        address minority = address(0xA11CE);
        address majority = address(0xB0B);
        _depositVotes(gKton, minority, 3_500e18);
        _depositVotes(gKton, majority, 6_000e18);
        vm.warp(block.timestamp + 1);

        GovernanceTarget target = new GovernanceTarget(dao.timelock());
        Proposal memory oldProposal = _proposeAndVote(
            dao, minority, address(target), abi.encodeCall(GovernanceTarget.setValue, (42)), "Queued proposal"
        );
        vm.warp(dao.proposalDeadline(oldProposal.id) + 1);
        dao.queue(oldProposal.targets, oldProposal.values, oldProposal.calldatas, oldProposal.descriptionHash);
        assertEq(uint256(dao.state(oldProposal.id)), uint256(IGovernor.ProposalState.Queued));

        _changeQuorum(dao, majority, 5_000e18);
        assertEq(dao.quorum(), 5_000e18);
        assertEq(dao.quorum(dao.clock()), 5_000e18);

        assertGt(block.timestamp, dao.proposalEta(oldProposal.id));
        assertEq(dao.quorum(dao.proposalSnapshot(oldProposal.id)), 3_000e18);
        assertEq(uint256(dao.state(oldProposal.id)), uint256(IGovernor.ProposalState.Queued));
        dao.execute(oldProposal.targets, oldProposal.values, oldProposal.calldatas, oldProposal.descriptionHash);
        assertEq(target.value(), 42);
    }

    function _depositVotes(address gKton, address voter, uint256 amount) internal {
        underlying.mint(voter, amount);
        vm.startPrank(voter);
        underlying.approve(gKton, amount);
        IGKTON(gKton).depositFor(voter, amount);
        IGKTON(gKton).delegate(voter);
        vm.stopPrank();
    }

    function _proposeAndVote(KtonDAOV3 dao, address voter, address target, bytes memory data, string memory description)
        internal
        returns (Proposal memory p)
    {
        p.targets = new address[](1);
        p.targets[0] = target;
        p.values = new uint256[](1);
        p.calldatas = new bytes[](1);
        p.calldatas[0] = data;
        p.descriptionHash = keccak256(bytes(description));
        vm.prank(voter);
        p.id = dao.propose(p.targets, p.values, p.calldatas, description);
        vm.warp(dao.proposalSnapshot(p.id) + 1);
        vm.prank(voter);
        dao.castVote(p.id, 1);
    }

    function _changeQuorum(KtonDAOV3 dao, address voter, uint256 newQuorum) internal {
        Proposal memory p = _proposeAndVote(
            dao, voter, address(dao), abi.encodeCall(KtonDAOV3.updateQuorum, (newQuorum)), "Change quorum"
        );
        vm.warp(dao.proposalDeadline(p.id) + 1);
        dao.queue(p.targets, p.values, p.calldatas, p.descriptionHash);
        vm.warp(dao.proposalEta(p.id));
        dao.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
    }
}

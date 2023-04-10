// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {AgentManager} from "../../../contracts/manager/AgentManager.sol";
import {ISystemRegistry} from "../../../contracts/interfaces/ISystemRegistry.sol";
import {AgentFlag, SlashStatus, SystemEntity} from "../../../contracts/libs/Structures.sol";

import {SystemEntity, SystemRouterHarness} from "../../harnesses/system/SystemRouterHarness.t.sol";
import {SystemContractTest} from "../system/SystemContract.t.sol";

// solhint-disable func-name-mixedcase
// solhint-disable ordering
abstract contract AgentManagerTest is SystemContractTest {
    uint256 internal rootSubmittedAt;

    function test_setup() public virtual {
        assertEq(address(testedAM().destination()), localDestination());
        assertEq(address(testedAM().origin()), localOrigin());
        assertEq(testedAM().agentRoot(), getAgentRoot());
    }

    // ═══════════════════════════════════════════ TESTS: REGISTRY SLASH ═══════════════════════════════════════════════

    function test_registrySlash_revertUnauthorized(address caller) public {
        vm.assume(!isLocalSystemRegistry(caller));
        vm.expectRevert("Unauthorized caller");
        vm.prank(caller);
        // Try to slash an existing agent
        testedAM().registrySlash(0, domains[0].agent, address(0));
    }

    function test_registrySlash_origin(uint256 domainId, uint256 agentId, address prover) public {
        _test_registrySlash(true, domainId, agentId, prover);
    }

    function test_registrySlash_destination(uint256 domainId, uint256 agentId, address prover) public {
        _test_registrySlash(false, domainId, agentId, prover);
    }

    function _test_registrySlash(bool onOrigin, uint256 domainId, uint256 agentId, address prover) internal {
        address registryF = onOrigin ? localOrigin() : localDestination();
        address registryS = onOrigin ? localDestination() : localOrigin();
        (uint32 domain, address agent) = getAgent(domainId, agentId);
        vm.expectEmit();
        emit StatusUpdated(AgentFlag.Fraudulent, domain, agent);
        // Expect call to the second registry
        vm.expectCall(registryS, abi.encodeWithSelector(ISystemRegistry.managerSlash.selector, domain, agent));
        // Prank call from the first registry
        vm.prank(registryF);
        testedAM().registrySlash(domain, agent, prover);
        assertEq(uint8(testedAM().agentStatus(agent).flag), uint8(AgentFlag.Fraudulent));
        (bool isSlashed, address prover_) = testedAM().slashStatus(agent);
        assertTrue(isSlashed);
        assertEq(prover_, prover);
    }

    // ══════════════════════════════════════════════════ HELPERS ══════════════════════════════════════════════════════

    function skipBondingOptimisticPeriod() public {
        skipPeriod(BONDING_OPTIMISTIC_PERIOD);
    }

    function skipPeriod(uint256 period) public {
        rootSubmittedAt = block.timestamp;
        skip(period);
    }

    function systemPrank(SystemRouterHarness router, uint32 callOrigin, SystemEntity systemCaller, bytes memory payload)
        public
    {
        router.systemPrank({
            recipient: SystemEntity.AgentManager,
            proofMaturity: block.timestamp - rootSubmittedAt,
            callOrigin: callOrigin,
            systemCaller: systemCaller,
            payload: payload
        });
    }

    function remoteSlashPayload(uint32 domain, address agent, address prover) public view returns (bytes memory) {
        // (proofMaturity, callOrigin, systemCaller) are omitted; (domain, agent, prover)
        return abi.encodeWithSelector(bondingManager.remoteRegistrySlash.selector, domain, agent, prover);
    }

    /// @notice Returns address of the tested system contract
    function systemContract() public view override returns (address) {
        return localAgentManager();
    }

    /// @notice Returns tested system contract as AgentManager
    function testedAM() public view returns (AgentManager) {
        return AgentManager(localAgentManager());
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { InterfaceSystemRouter } from "../../../contracts/interfaces/InterfaceSystemRouter.sol";
import { SystemContract } from "../../../contracts/system/SystemContract.sol";
import { DomainContext } from "../../../contracts/context/DomainContext.sol";
import "../events/SystemContractMockEvents.sol";

// solhint-disable no-empty-blocks
contract SystemContractMock is SystemContractMockEvents, SystemContract {
    // Expose internal constants for tests
    uint256 public constant ORIGIN_MASK = ORIGIN;
    uint256 public constant DESTINATION_MASK = DESTINATION;
    uint256 public constant BONDING_MANAGER_MASK = BONDING_MANAGER;

    uint256 public constant BONDING_OPTIMISTIC_PERIOD_PUB = BONDING_OPTIMISTIC_PERIOD;

    constructor(uint32 _domain) DomainContext(_domain) {}

    function initialize() external initializer {
        __SystemContract_initialize();
    }

    // Expose modifiers for tests
    function mockOnlySystemRouter() external onlySystemRouter {}

    function mockOnlySynapseChain(uint32 domain) external onlySynapseChain(domain) {}

    function mockOnlyCallers(uint256 mask, InterfaceSystemRouter.SystemEntity caller)
        external
        onlyCallers(mask, caller)
    {}

    function mockOnlyOptimisticPeriodOver(uint256 rootSubmittedAt, uint256 optimisticSeconds)
        external
        onlyOptimisticPeriodOver(rootSubmittedAt, optimisticSeconds)
    {}

    function slashAgent(
        uint256,
        uint32,
        InterfaceSystemRouter.SystemEntity,
        AgentInfo memory _info
    ) external override {
        emit SlashAgentCall(_info);
    }

    function syncAgents(
        uint256,
        uint32,
        InterfaceSystemRouter.SystemEntity,
        uint256 _requestID,
        bool _removeExisting,
        AgentInfo[] memory _infos
    ) external override {
        emit SyncAgentsCall(_requestID, _removeExisting, _infos);
    }
}

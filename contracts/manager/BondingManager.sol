// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
// ══════════════════════════════ LIBRARY IMPORTS ══════════════════════════════
import { AgentFlag, AgentStatus, SlashStatus, SystemEntity } from "../libs/Structures.sol";
import { DynamicTree, MerkleLib } from "../libs/Merkle.sol";
import { MerkleList } from "../libs/MerkleList.sol";
// ═════════════════════════════ INTERNAL IMPORTS ══════════════════════════════
import { AgentManager, IAgentManager, ISystemRegistry } from "./AgentManager.sol";
import { DomainContext } from "../context/DomainContext.sol";
import { IBondingManager } from "../interfaces/IBondingManager.sol";
import { Versioned } from "../Version.sol";

/// @notice BondingManager keeps track of all existing agents.
/// Used on the Synapse Chain, serves as the "source of truth" for LightManagers on remote chains.
contract BondingManager is Versioned, AgentManager, IBondingManager {
    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                               STORAGE                                ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    // (agent => their status)
    mapping(address => AgentStatus) private agentMap;

    // A list of all agent accounts. First entry is address(0) to make agent indexes start from 1.
    address[] private agents;

    // Merkle Tree for Agents.
    // leafs[0] = 0
    // leafs[index > 0] = keccak(agentFlag, domain, agents[index])
    DynamicTree private agentTree;

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                      CONSTRUCTOR & INITIALIZER                       ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    constructor(uint32 _domain) DomainContext(_domain) Versioned("0.0.3") {
        require(_onSynapseChain(), "Only deployed on SynChain");
    }

    function initialize(ISystemRegistry _origin, ISystemRegistry _destination)
        external
        initializer
    {
        __AgentManager_init(_origin, _destination);
        __Ownable_init();
        // Insert a zero address to make indexes for Agents start from 1.
        // Zeroed index is supposed to be used as a sentinel value meaning "no agent".
        agents.push(address(0));
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                          AGENTS LOGIC (MVP)                          ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    // TODO: remove these MVP functions once token staking is implemented

    /// @inheritdoc IBondingManager
    function addAgent(
        uint32 _domain,
        address _agent,
        bytes32[] memory _proof
    ) external onlyOwner {
        // Check current status of the added agent
        AgentStatus memory status = _agentStatus(_agent);
        // Agent index in `agents`
        uint32 index;
        // Leaf representing currently saved agent information in the tree
        bytes32 oldValue;
        if (status.flag == AgentFlag.Unknown) {
            // Unknown address could be added to any domain
            // New agent will need to be added to `agents` list
            require(agents.length < type(uint32).max, "Agents list if full");
            index = uint32(agents.length);
            // Current leaf for index is bytes32(0), which is already assigned to `leaf`
            agents.push(_agent);
        } else if (status.flag == AgentFlag.Resting && status.domain == _domain) {
            // Resting agent could be only added back to the same domain
            // Agent is already in `agents`, fetch the saved index
            index = status.index;
            // Generate the current leaf for the agent
            // oldValue includes the domain information, so we didn't had to check it above.
            // However, we are still doing this check to have a more appropriate revert string,
            // if a resting agent is requesting to be added to another domain.
            oldValue = _agentLeaf(AgentFlag.Resting, _domain, _agent);
        } else {
            // Any other flag indicates that agent could not be added
            revert("Agent could not be added");
        }
        // This will revert if the proof for the old value is incorrect
        _updateLeaf(oldValue, _proof, AgentStatus(AgentFlag.Active, _domain, index), _agent);
    }

    /// @inheritdoc IBondingManager
    function initiateUnstaking(
        uint32 _domain,
        address _agent,
        bytes32[] memory _proof
    ) external onlyOwner {
        // Check current status of the unstaking agent
        AgentStatus memory status = _agentStatus(_agent);
        // Could only initiate the unstaking for the active agent for the domain
        require(
            status.flag == AgentFlag.Active && status.domain == _domain,
            "Unstaking could not be initiated"
        );
        // Leaf representing currently saved agent information in the tree.
        // oldValue includes the domain information, so we didn't had to check it above.
        // However, we are still doing this check to have a more appropriate revert string,
        // if an agent is initiating the unstaking, but specifies incorrect domain.
        bytes32 oldValue = _agentLeaf(AgentFlag.Active, _domain, _agent);
        // This will revert if the proof for the old value is incorrect
        _updateLeaf(
            oldValue,
            _proof,
            AgentStatus(AgentFlag.Unstaking, _domain, status.index),
            _agent
        );
    }

    /// @inheritdoc IBondingManager
    function completeUnstaking(
        uint32 _domain,
        address _agent,
        bytes32[] memory _proof
    ) external onlyOwner {
        // Check current status of the unstaking agent
        AgentStatus memory status = _agentStatus(_agent);
        // Could only complete the unstaking, if it was previously initiated
        // TODO: add more checks (time-based, possibly collecting info from other chains)
        require(
            status.flag == AgentFlag.Unstaking && status.domain == _domain,
            "Unstaking could not be completed"
        );
        // Leaf representing currently saved agent information in the tree
        // oldValue includes the domain information, so we didn't had to check it above.
        // However, we are still doing this check to have a more appropriate revert string,
        // if an agent is completing the unstaking, but specifies incorrect domain.
        bytes32 oldValue = _agentLeaf(AgentFlag.Unstaking, _domain, _agent);
        // This will revert if the proof for the old value is incorrect
        _updateLeaf(
            oldValue,
            _proof,
            AgentStatus(AgentFlag.Resting, _domain, status.index),
            _agent
        );
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                            SLASHING LOGIC                            ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @inheritdoc IBondingManager
    function completeSlashing(
        uint32 _domain,
        address _agent,
        bytes32[] memory _proof
    ) external {
        // Check that slashing was initiated by one of the System Registries
        require(slashStatus[_agent].isSlashed, "Slashing not initiated");
        // Check that agent is Active/Unstaking and that the domains match
        AgentStatus memory status = _agentStatus(_agent);
        require(
            (status.flag == AgentFlag.Active || status.flag == AgentFlag.Unstaking) &&
                status.domain == _domain,
            "Slashing could not be completed"
        );
        // Leaf representing currently saved agent information in the tree
        // oldValue includes the domain information, so we didn't had to check it above.
        // However, we are still doing this check to have a more appropriate revert string,
        // if anyone is completing the slashing, but specifies incorrect domain.
        bytes32 oldValue = _agentLeaf(status.flag, _domain, _agent);
        // This will revert if the proof for the old value is incorrect
        _updateLeaf(
            oldValue,
            _proof,
            AgentStatus(AgentFlag.Slashed, _domain, status.index),
            _agent
        );
    }

    /// @inheritdoc IAgentManager
    function registrySlash(
        uint32 _domain,
        address _agent,
        address _prover
    ) external {
        // Check that Agent hasn't been already slashed and initiate the slashing
        _initiateSlashing(_domain, _agent, _prover);
        // On SynChain both Origin and Destination (Summit) could slash agents
        if (msg.sender == address(origin)) {
            _notifySlashing(DESTINATION, _domain, _agent, _prover);
        } else if (msg.sender == address(destination)) {
            _notifySlashing(ORIGIN, _domain, _agent, _prover);
        } else {
            revert("Unauthorized caller");
        }
    }

    /// @inheritdoc IBondingManager
    function remoteRegistrySlash(
        uint256 _rootSubmittedAt,
        uint32 _callOrigin,
        SystemEntity _systemCaller,
        uint32 _domain,
        address _agent,
        address _prover
    )
        external
        onlySystemRouter
        onlyCallers(AGENT_MANAGER, _systemCaller)
        onlyOptimisticPeriodOver(_rootSubmittedAt, BONDING_OPTIMISTIC_PERIOD)
    {
        // TODO: do we need to save this?
        _callOrigin;
        // Check that Agent hasn't been already slashed and initiate the slashing
        _initiateSlashing(_domain, _agent, _prover);
        // Notify local registries about the slashing
        _notifySlashing(DESTINATION | ORIGIN, _domain, _agent, _prover);
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                                VIEWS                                 ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @inheritdoc IAgentManager
    function agentRoot() external view override returns (bytes32) {
        return agentTree.root;
    }

    /// @inheritdoc IBondingManager
    function agentLeaf(address _agent) external view returns (bytes32 leaf) {
        return _getLeaf(_agent);
    }

    /// @inheritdoc IBondingManager
    function leafsAmount() external view returns (uint256 amount) {
        return agents.length;
    }

    /// @inheritdoc IBondingManager
    function getProof(address _agent) external view returns (bytes32[] memory proof) {
        bytes32[] memory leafs = allLeafs();
        AgentStatus memory status = _agentStatus(_agent);
        // Use next available index for unknown agents
        uint256 index = status.flag == AgentFlag.Unknown ? agents.length : status.index;
        return MerkleList.calculateProof(leafs, index);
    }

    /// @inheritdoc IBondingManager
    function allLeafs() public view returns (bytes32[] memory leafs) {
        return getLeafs(0, agents.length);
    }

    /// @inheritdoc IBondingManager
    function getLeafs(uint256 _indexFrom, uint256 _amount)
        public
        view
        returns (bytes32[] memory leafs)
    {
        uint256 amountTotal = agents.length;
        require(_indexFrom < amountTotal, "Out of range");
        if (_indexFrom + _amount > amountTotal) {
            _amount = amountTotal - _indexFrom;
        }
        leafs = new bytes32[](_amount);
        for (uint256 i = 0; i < _amount; ++i) {
            leafs[i] = _getLeaf(_indexFrom + i);
        }
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                            INTERNAL LOGIC                            ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Updates value in the Agent Merkle Tree to reflect the `_newStatus`.
    /// Will revert, if supplied proof for the old value is incorrect.
    function _updateLeaf(
        bytes32 _oldValue,
        bytes32[] memory _proof,
        AgentStatus memory _newStatus,
        address _agent
    ) internal {
        // New leaf value for the agent in the Agent Merkle Tree
        bytes32 newValue = _agentLeaf(_newStatus.flag, _newStatus.domain, _agent);
        // This will revert if the proof for the old value is incorrect
        bytes32 newRoot = agentTree.update(_newStatus.index, _oldValue, _proof, newValue);
        agentMap[_agent] = _newStatus;
        emit StatusUpdated(_newStatus.flag, _newStatus.domain, _agent);
        emit RootUpdated(newRoot);
    }

    /// @dev Returns the status of the agent.
    function _agentStatus(address _agent) internal view override returns (AgentStatus memory) {
        return agentMap[_agent];
    }

    /// @dev Returns the current leaf representing agent in the Agent Merkle Tree.
    function _getLeaf(address _agent) internal view returns (bytes32 leaf) {
        AgentStatus memory status = _agentStatus(_agent);
        if (status.flag != AgentFlag.Unknown) {
            return _agentLeaf(status.flag, status.domain, _agent);
        }
        // Return empty leaf for unknown agents
    }

    /// @dev Returns a leaf from the Agent Merkle Tree with a given index.
    function _getLeaf(uint256 index) internal view returns (bytes32 leaf) {
        if (index != 0) {
            return _getLeaf(agents[index]);
        }
        // Return empty leaf for a zero index
    }
}

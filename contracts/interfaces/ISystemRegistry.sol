// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ISystemRegistry {
    /**
     * @notice Local AgentManager should call this function to indicate that the agent
     * has been slashed, either on local or remote chain.
     * @param _domain   Domain where the slashed agent was active
     * @param _agent    Address of the slashed Agent
     */
    function managerSlash(uint32 _domain, address _agent) external;

    /**
     * @notice Returns true if the agent is active on any domain.
     * Note: that includes both Guards and Notaries.
     * @return isActive Whether the account is an active agent on any of the domains
     * @return domain   Domain, where the account is an active agent
     */
    function isActiveAgent(address _account) external view returns (bool isActive, uint32 domain);

    /**
     * @notice Returns true if the agent is active on the given domain.
     * Note: domain == 0 refers to a Guard, while _domain > 0 refers to a Notary.
     */
    function isActiveAgent(uint32 _domain, address _account) external view returns (bool);
}

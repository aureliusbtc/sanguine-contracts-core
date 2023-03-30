// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract DisputeHubEvents {
    /**
     * @notice Emitted when a Dispute between a Guard and a Notary is initiated
     * by a Guard submitting a Report on invalid statement signed by a Notary.
     * @param guard     Address of the Guard who submitted a Report
     * @param domain    Domain where the Notary is active
     * @param notary    Address of the Notary who signed a reported statement
     */
    event Dispute(address guard, uint32 domain, address notary);

    /**
     * @notice Emitted when a Dispute between a Guard and a Notary is resolved
     * by any of the agents getting slashed.
     * @param honest    The address of the agent who wasn't slashed
     * @param domain    Domain where the slashed agent was active
     * @param slashed   The address of the agent who was slashed
     */
    event DisputeResolved(address honest, uint32 domain, address slashed);
}

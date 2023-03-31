// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;
// ══════════════════════════════ LIBRARY IMPORTS ══════════════════════════════
import { DisputeFlag, DisputeStatus } from "../libs/Structures.sol";
// ═════════════════════════════ INTERNAL IMPORTS ══════════════════════════════
import { AgentStatus, Attestation, Snapshot, StatementHub, StateReport } from "./StatementHub.sol";
import { DisputeHubEvents } from "../events/DisputeHubEvents.sol";
import { IDisputeHub } from "../interfaces/IDisputeHub.sol";

abstract contract DisputeHub is StatementHub, DisputeHubEvents, IDisputeHub {
    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                               STORAGE                                ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    // (agent => their dispute status)
    mapping(address => DisputeStatus) internal _disputes;

    /// @dev gap for upgrade safety
    uint256[49] private __GAP; // solhint-disable-line var-name-mixedcase

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                        INITIATE DISPUTE LOGIC                        ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @inheritdoc IDisputeHub
    function submitStateReport(
        uint256 stateIndex,
        bytes memory srPayload,
        bytes memory srSignature,
        bytes memory snapPayload,
        bytes memory snapSignature
    ) external returns (bool wasAccepted) {
        // Call the hook and check if we can accept the statement
        if (!_beforeStatement()) return false;
        // This will revert if payload is not a state report
        StateReport report = _wrapStateReport(srPayload);
        // This will revert if the report signer is not an known Guard
        (AgentStatus memory guardStatus, address guard) = _verifyStateReport(report, srSignature);
        // Check that Guard is active
        _verifyActive(guardStatus);
        // This will revert if payload is not a snapshot
        Snapshot snapshot = _wrapSnapshot(snapPayload);
        // This will revert if the snapshot signer is not a known Agent
        (AgentStatus memory notaryStatus, address notary) = _verifySnapshot(
            snapshot,
            snapSignature
        );
        // Snapshot signer needs to be a Notary, not a Guard
        require(notaryStatus.domain != 0, "Snapshot signer is not a Notary");
        // Notary needs to be Active/Unstaking
        _verifyActiveUnstaking(notaryStatus);
        // Snapshot state and reported state need to be the same
        // This will revert if state index is out of range
        require(snapshot.state(stateIndex).equals(report.state()), "States don't match");
        // Reported State was used by the Notary for their signed snapshot => open dispute
        _openDispute(guard, notaryStatus.domain, notary);
        return true;
    }

    /// @inheritdoc IDisputeHub
    function submitStateReportWithProof(
        uint256 stateIndex,
        bytes memory srPayload,
        bytes memory srSignature,
        bytes32[] memory snapProof,
        bytes memory attPayload,
        bytes memory attSignature
    ) external returns (bool wasAccepted) {
        // Call the hook and check if we can accept the statement
        if (!_beforeStatement()) return false;
        // This will revert if payload is not a state report
        StateReport report = _wrapStateReport(srPayload);
        // This will revert if the report signer is not an known Guard
        (AgentStatus memory guardStatus, address guard) = _verifyStateReport(report, srSignature);
        // Check that Guard is active
        _verifyActive(guardStatus);
        // This will revert if payload is not an attestation
        Attestation att = _wrapAttestation(attPayload);
        // This will revert if signer is not a known Notary
        (AgentStatus memory notaryStatus, address notary) = _verifyAttestation(att, attSignature);
        // Notary needs to be Active/Unstaking
        _verifyActiveUnstaking(notaryStatus);
        // This will revert if any of these is true:
        //  - Attestation root is not equal to Merkle Root derived from State and Snapshot Proof.
        //  - Snapshot Proof's first element does not match the State metadata.
        //  - Snapshot Proof length exceeds Snapshot tree Height.
        //  - State index is out of range.
        _verifySnapshotMerkle(att, stateIndex, report.state(), snapProof);
        // Reported State was used by the Notary for their signed attestation => open dispute
        _openDispute(guard, notaryStatus.domain, notary);
        return true;
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                                VIEWS                                 ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @inheritdoc IDisputeHub
    function disputeStatus(address agent) external view returns (DisputeStatus memory status) {
        return _disputes[agent];
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                            INTERNAL LOGIC                            ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Hook that is called before every statement is handled.
    /// @return acceptNext  Whether to accept the next statement
    function _beforeStatement() internal virtual returns (bool acceptNext);

    /// @dev Opens a Dispute between a Guard and a Notary.
    /// This should be called, when the Guard submits a Report on a statement signed by the Notary.
    function _openDispute(
        address guard,
        uint32 domain,
        address notary
    ) internal virtual {
        // Check that both agents are not in Dispute yet
        require(_disputes[guard].flag == DisputeFlag.None, "Guard already in dispute");
        require(_disputes[notary].flag == DisputeFlag.None, "Notary already in dispute");
        _disputes[guard] = DisputeStatus(DisputeFlag.Pending, notary);
        _disputes[notary] = DisputeStatus(DisputeFlag.Pending, guard);
        emit Dispute(guard, domain, notary);
    }

    /// @dev This is called when the slashing was initiated in this contract or elsewhere.
    function _processSlashed(
        uint32 domain,
        address agent,
        address prover
    ) internal virtual override {
        _resolveDispute(domain, agent);
        super._processSlashed(domain, agent, prover);
    }

    /// @dev Resolves a Dispute for a slashed agent, if it hasn't been done already.
    function _resolveDispute(uint32 domain, address slashedAgent) internal virtual {
        DisputeStatus memory status = _disputes[slashedAgent];
        // Do nothing if dispute was already resolved
        if (status.flag == DisputeFlag.Slashed) return;
        // Update flag for the slashed agent
        // Slashed agent might have had no open Dispute, meaning the `counterpart` could be ZERO.
        // We still want to have the DisputeFlag.Slashed assigned in this case.
        _disputes[slashedAgent].flag = DisputeFlag.Slashed;
        // Delete record of dispute for the counterpart. This sets their Dispute Flag to None.
        if (status.counterpart != address(0)) delete _disputes[status.counterpart];
        // TODO: wo we want to use prover address if there was no counterpart?
        emit DisputeResolved(status.counterpart, domain, slashedAgent);
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                            INTERNAL VIEWS                            ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    /// @dev Checks if an agent is currently in Dispute.
    function _inDispute(address agent) internal view returns (bool) {
        return _disputes[agent].flag != DisputeFlag.None;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {InterfaceSummit} from "../../contracts/interfaces/InterfaceSummit.sol";
import {SnapshotHubMock} from "./hubs/SnapshotHubMock.t.sol";
import {SystemContractMock} from "./system/SystemContractMock.t.sol";
import {SystemRegistryMock} from "./system/SystemRegistryMock.t.sol";

// solhint-disable no-empty-blocks
contract SummitMock is SnapshotHubMock, SystemContractMock, SystemRegistryMock, InterfaceSummit {
    /// @notice Prevents this contract from being included in the coverage report
    function testSummitMock() external {}

    function submitSnapshot(bytes memory snapPayload, bytes memory snapSignature)
        external
        returns (bytes memory attPayload)
    {}

    function verifyAttestation(bytes memory attPayload, bytes memory attSignature) external returns (bool isValid) {}

    function verifyAttestationReport(bytes memory arPayload, bytes memory arSignature)
        external
        returns (bool isValid)
    {}

    function getLatestState(uint32 origin) external view returns (bytes memory statePayload) {}
}

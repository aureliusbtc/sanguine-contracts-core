// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { AttestationCollector } from "../../contracts/AttestationCollector.sol";

contract AttestationCollectorHarness is AttestationCollector {
    function isNotary(uint32 _domain, address _notary) public view returns (bool) {
        return _isActiveAgent(_domain, _notary);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import { MerkleList } from "../../../contracts/libs/MerkleList.sol";

contract MerkleListHarness {
    // Note: we don't add an empty test() function here, as it currently leads
    // to zero coverage on the corresponding library.

    function calculateRoot(bytes32[] memory hashes) public pure returns (bytes32) {
        MerkleList.calculateRoot(hashes);
        return hashes[0];
    }

    function calculateProof(bytes32[] memory hashes, uint256 index)
        public
        pure
        returns (bytes32[] memory proof)
    {
        uint256 height = 1;
        uint256 amount = 1;
        while (amount < hashes.length) {
            amount *= 2;
            ++height;
        }
        proof = new bytes32[](height);
        MerkleList.calculateProof(hashes, index, proof);
    }
}

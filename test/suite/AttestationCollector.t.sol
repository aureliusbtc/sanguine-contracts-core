// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../tools/AttestationCollectorTools.t.sol";

// solhint-disable func-name-mixedcase
contract AttestationCollectorTest is AttestationCollectorTools {
    function setUp() public override {
        super.setUp();
        setupAttestationCollector();
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                   TESTS: CONSTRUCTOR & INITIALIZER                   ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    function test_initializedCorrectly() public {
        setupAttestationCollector();
        assertEq(attestationCollector.owner(), owner, "!owner");
    }

    function test_initialize_revert_onlyOnce() public {
        expectRevertAlreadyInitialized();
        attestationCollector.initialize();
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                          TESTS: ADD NOTARY                           ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    function test_addNotary() public {
        vm.startPrank(owner);
        for (uint256 d = 0; d < DOMAINS; ++d) {
            uint32 domain = domains[d];
            for (uint256 i = 0; i < NOTARIES_PER_CHAIN; ++i) {
                attestationCollectorAddNotary({
                    domain: domain,
                    notaryIndex: i,
                    returnValue: true
                });
                assertTrue(
                    attestationCollectorIsNotary({ domain: domain, notaryIndex: i }),
                    "Failed to add Notary"
                );
            }
        }
        vm.stopPrank();
    }

    function test_addNotary_revert_notOwner(address caller) public {
        vm.assume(caller != owner);
        vm.startPrank(caller);
        attestationCollectorAddNotary({
            domain: DOMAIN_LOCAL,
            notaryIndex: 0,
            revertMessage: REVERT_NOT_OWNER
        });
        vm.stopPrank();
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                         TESTS: REMOVE NOTARY                         ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    function test_removeNotary() public {
        test_addNotary();
        vm.startPrank(owner);
        for (uint256 d = 0; d < DOMAINS; ++d) {
            uint32 domain = domains[d];
            for (uint256 i = 0; i < NOTARIES_PER_CHAIN; ++i) {
                attestationCollectorRemoveNotary({
                    domain: domain,
                    notaryIndex: i,
                    returnValue: true
                });
                assertFalse(
                    attestationCollectorIsNotary({ domain: domain, notaryIndex: i }),
                    "Failed to add Notary"
                );
            }
        }
        vm.stopPrank();
    }

    function test_removeNotary_revert_notOwner(address caller) public {
        vm.assume(caller != owner);
        test_addNotary();
        vm.startPrank(caller);
        attestationCollectorRemoveNotary({
            domain: DOMAIN_LOCAL,
            notaryIndex: 0,
            revertMessage: REVERT_NOT_OWNER
        });
        vm.stopPrank();
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                 TESTS: SUBMIT ATTESTATION (REVERTS)                  ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    function test_submitAttestation_revert_notNotary_attacker() public {
        test_addNotary();
        createAttestationMock({
            origin: DOMAIN_LOCAL,
            destination: DOMAIN_REMOTE,
            signer: attacker
        });
        // Check that attacker (address unknown to AttestationCollector) can't sign the attestation
        // Some random address should not be considered a Notary for `DOMAIN_LOCAL`
        attestationCollectorSubmitAttestation({ revertMessage: "Signer is not a notary" });
    }

    function test_submitAttestation_revert_notNotary_notaryAnotherDomain() public {
        test_addNotary();
        createAttestationMock({
            origin: DOMAIN_LOCAL,
            destination: DOMAIN_REMOTE,
            signer: suiteNotary(DOMAIN_LOCAL)
        });
        // Check that Notary from another domain can't sign the attestation to `DOMAIN_REMOTE`
        // Notary from `DOMAIN_LOCAL` should not be considered as a Notary for `DOMAIN_REMOTE`
        attestationCollectorSubmitAttestation({ revertMessage: "Signer is not a notary" });
    }

    function test_submitAttestation_revert_zeroNonce() public {
        test_addNotary();
        // Create attestation with a zero nonce
        createAttestationMock({ origin: DOMAIN_LOCAL, destination: DOMAIN_REMOTE, nonce: 0 });
        // When Notary hasn't submitted a single attestation, they should not be able
        // to submit attestation with `nonce = 0`. It will be marked as "outdated", as it
        // doesn't bring new information about the Origin merkle state.
        attestationCollectorSubmitAttestation({ revertMessage: "Outdated attestation" });
    }

    function test_submitAttestation_revert_sameNonce() public {
        test_submitAttestation();
        // When Notary submitted an attestation, they should not be able to submit the
        // same attestation again.  It will be marked as "outdated", as it
        // doesn't bring new information about the Origin merkle state.
        // No need to recreate the attestation, as it is saved after `test_submitAttestation()`
        attestationCollectorSubmitAttestation({ revertMessage: "Outdated attestation" });
    }

    function test_submitAttestation_revert_outdatedNonce() public {
        test_submitAttestation();
        // Create attestation with a nonce lower than of already submitted attestation
        createAttestationMock({
            origin: currentOrigin,
            destination: currentDestination,
            nonce: attestationNonce - 1
        });
        // When Notary submitted an attestation with, they should not be able to submit the
        // attestation with a lower nonce.  It will be marked as "outdated", as it
        // doesn't bring new information about the Origin merkle state.
        attestationCollectorSubmitAttestation({ revertMessage: "Outdated attestation" });
    }

    function test_submitAttestation_revert_duplicate() public {
        test_submitAttestation();
        // Create attestation for the same merkle state, but signed by another Notary
        createAttestationMock({
            origin: currentOrigin,
            destination: currentDestination,
            nonce: attestationNonce,
            notaryIndex: 1,
            salt: 0
        });
        // Attestation that duplicates the already existing one is not accepted, as it
        // doesn't bring new information about the Origin merkle state.
        attestationCollectorSubmitAttestation({ revertMessage: "Duplicated attestation" });
        // TODO: potentially accept duplicated attestations in the future?
        // Measure "data credibility" as the amount of actors who signed it?
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                      TESTS: SUBMIT ATTESTATION                       ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    function test_submitAttestation() public {
        test_addNotary();
        currentOrigin = DOMAIN_LOCAL;
        currentDestination = DOMAIN_REMOTE;
        submitTestAttestation({ nonce: NONCE_TEST, notaryIndex: 0, isUnique: true });
    }

    function test_submitAttestation_anotherNotary_outdatedNonce() public {
        test_submitAttestation();
        // ANOTHER notary can sign and submit an attestation with a lower nonce.
        // Such attestation should be accepted, otherwise a rogue Notary can submit
        // a fraud attestation with absurdly big nonce to brick the system.
        submitTestAttestation({ nonce: NONCE_TEST - 1, notaryIndex: 1, isUnique: true });
    }

    function test_submitAttestation_anotherNotary_sameNonceAnotherRoot() public {
        test_submitAttestation();
        // Another notary can sign and submit an attestation with same nonce, but different root.
        // Meaning one of the two attestations is fraudulent. Such attestation should be accepted,
        // otherwise "the first submitted" attestation becomes the source of truth
        submitTestAttestation({ nonce: NONCE_TEST, notaryIndex: 1, isUnique: true });
    }

    function test_submitAttestations() public {
        test_addNotary();
        for (uint256 o = 0; o < DOMAINS; ++o) {
            currentOrigin = domains[o];

            for (uint256 d = 0; d < DOMAINS; ++d) {
                if (o == d) continue;
                currentDestination = domains[d];
                // Notary[0] submits attestations with nonces: [1, 2, 5]
                // All thNew nonce: will be accepted (next three)
                submitTestAttestation({ nonce: 1, notaryIndex: 0, isUnique: true });
                submitTestAttestation({ nonce: 2, notaryIndex: 0, isUnique: true });
                submitTestAttestation({ nonce: 5, notaryIndex: 0, isUnique: true });

                // Notary[1] submits attestations with nonces: [1, 3, 6]
                // The same root as Notary[0]: will not be accepted
                submitTestAttestation({ nonce: 1, notaryIndex: 1, salt: 0, isUnique: false });
                // New nonce: will be accepted (next two)
                submitTestAttestation({ nonce: 3, notaryIndex: 1, isUnique: true });
                submitTestAttestation({ nonce: 6, notaryIndex: 1, isUnique: true });

                // Notary[2] submits nonces [1, 6, 7]
                // Root is different from one submitted by Notary[0]: will be accepted
                submitTestAttestation({ nonce: 1, notaryIndex: 2, isUnique: true });
                // Root is different from one submitted by Notary[1]: will be accepted
                submitTestAttestation({ nonce: 6, notaryIndex: 2, isUnique: true });
                // New nonce: will be accepted
                submitTestAttestation({ nonce: 7, notaryIndex: 2, isUnique: true });

                // Notary[3] submits all existing duplicate attestations for nonces [1, 6]

                // The same root as Notary[0]: will not be accepted
                submitTestAttestation({ nonce: 1, notaryIndex: 3, salt: 0, isUnique: false });
                // The same root as Notary[2]: will not be accepted
                submitTestAttestation({ nonce: 1, notaryIndex: 3, salt: 2, isUnique: false });
                // The same root as Notary[1]: will not be accepted
                submitTestAttestation({ nonce: 6, notaryIndex: 3, salt: 1, isUnique: false });
                // The same root as Notary[2]: will not be accepted
                submitTestAttestation({ nonce: 6, notaryIndex: 3, salt: 2, isUnique: false });

                // Submit a few fresh attestations
                submitTestAttestation({ nonce: 9, notaryIndex: 2, isUnique: true });
                submitTestAttestation({ nonce: 10, notaryIndex: 0, isUnique: true });
                // The biggest nonce
                submitTestAttestation({ nonce: NONCE_TEST, notaryIndex: 3, isUnique: true });
                submitTestAttestation({ nonce: 8, notaryIndex: 1, isUnique: true });
            }
        }
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                        TESTS: VIEWS (REVERTS)                        ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    function test_getAttestation_revert_noSignature() public {
        test_submitAttestations();
        // Nonce 6 was submitted only by Notaries 1 and 2
        attestationCollectorGetAttestationByRoot({
            origin: DOMAIN_LOCAL,
            destination: DOMAIN_REMOTE,
            nonce: 6,
            root: _createMockRoot(6, 0),
            revertMessage: "!signature"
        });
    }

    function test_getLatestAttestation_revert_noNotaryAttestations() public {
        test_submitAttestation();
        // Attestation was submitted only for (origin, destination):
        // origin = currentOrigin
        // destination = currentDestination
        // Therefore there should be no attestations for the reversed pair
        attestationCollectorGetLatestNotaryAttestation({
            origin: currentDestination,
            destination: currentOrigin,
            notaryIndex: 0,
            revertMessage: "No attestations found"
        });
    }

    function test_getLatestAttestation_revert_noAttestations() public {
        test_submitAttestation();
        // Attestation was submitted only for (origin, destination):
        // origin = currentOrigin
        // destination = currentDestination
        // Therefore there should be no attestations for the reversed pair
        attestationCollectorGetLatestDomainAttestation({
            origin: currentDestination,
            destination: currentOrigin,
            revertMessage: "No attestations found"
        });
    }

    function test_getLatestAttestation_noNotaries() public {
        // Don't add any Notaries
        for (uint256 o = 0; o < DOMAINS; ++o) {
            for (uint256 d = 0; d < DOMAINS; ++d) {
                attestationCollectorGetLatestDomainAttestation({
                    origin: domains[o],
                    destination: domains[d],
                    revertMessage: "!notaries"
                });
            }
        }
    }

    /*╔══════════════════════════════════════════════════════════════════════╗*\
    ▏*║                             TESTS: VIEWS                             ║*▕
    \*╚══════════════════════════════════════════════════════════════════════╝*/

    // solhint-disable-next-line code-complexity
    function test_getAttestation_getRoot_rootsAmount() public {
        // Test for following getters (which are used the same testing conditions):
        // getAttestation(), getRoot(), rootsAmount()
        test_submitAttestations();
        for (uint256 o = 0; o < DOMAINS; ++o) {
            uint32 origin = domains[o];
            for (uint256 d = 0; d < DOMAINS; ++d) {
                if (o == d) continue;
                uint32 destination = domains[d];
                for (uint32 nonce = 1; nonce <= NONCE_TEST; ++nonce) {
                    uint96 _key = Attestation.attestationKey(origin, destination, nonce);
                    bytes[] memory attestations = keyAttestations[_key];
                    bytes32[] memory roots = keyRoots[_key];
                    uint256 amount = roots.length;
                    assertEq(
                        attestationCollector.rootsAmount(origin, destination, nonce),
                        amount,
                        "!rootsAmount()"
                    );
                    for (uint256 index = 0; index < amount; ++index) {
                        bytes memory attestation = attestations[index];
                        bytes32 root = roots[index];
                        assertEq(
                            attestationCollector.getAttestation(origin, destination, nonce, index),
                            attestation,
                            "!getAttestation(index)"
                        );
                        assertEq(
                            attestationCollector.getAttestation(origin, destination, nonce, root),
                            attestation,
                            "!getAttestation(root)"
                        );
                        assertEq(
                            attestationCollector.getRoot(origin, destination, nonce, index),
                            root,
                            "!geRoot(index)"
                        );
                    }
                    // Check for out of range reverts
                    vm.expectRevert("!index");
                    attestationCollector.getAttestation({
                        _origin: origin,
                        _destination: destination,
                        _nonce: nonce,
                        _index: amount
                    });
                    vm.expectRevert("!index");
                    attestationCollector.getRoot({
                        _origin: origin,
                        _destination: destination,
                        _nonce: nonce,
                        _index: amount
                    });
                }
            }
        }
    }
}

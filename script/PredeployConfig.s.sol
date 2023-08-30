// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ═════════════════════════════ INTERNAL IMPORTS ══════════════════════════════
import {DeployerUtils} from "./utils/DeployerUtils.sol";

import {CREATE3Factory} from "../contracts/create3/CREATE3Factory.sol";

import { DeployMessaging003SynChainScript } from "./DeployMessaging003SynChain.s.sol";
import {console, stdJson} from "forge-std/Script.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract PredeployConfig is DeployerUtils {
    using stdJson for string;
    using Strings for uint256;

    // Define addresses in Solidity format
    address constant BONDING_MANAGER = 0x420000000000000000000000000000000000002a;
    address constant DESTINATION = 0x420000000000000000000000000000000000002B;
    address constant GAS_ORACLE = 0x420000000000000000000000000000000000002C;
    address constant INBOX = 0x420000000000000000000000000000000000002d;
    address constant ORIGIN = 0x420000000000000000000000000000000000002E;
    address constant SUMMIT = 0x420000000000000000000000000000000000002F;

    constructor() {
        setupPK("MESSAGING_DEPLOYER_PRIVATE_KEY");
    }

    function run() external {
        startBroadcast(true);

        stopBroadcast();
    }
}
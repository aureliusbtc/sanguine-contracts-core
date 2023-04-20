// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

// ══════════════════════════════ LIBRARY IMPORTS ══════════════════════════════
import {Request, RequestLib} from "../libs/Request.sol";
import {Tips, TipsLib} from "../libs/Tips.sol";
import {TypeCasts} from "../libs/TypeCasts.sol";
// ═════════════════════════════ INTERNAL IMPORTS ══════════════════════════════
import {IMessageRecipient} from "../interfaces/IMessageRecipient.sol";
import {InterfaceOrigin} from "../interfaces/InterfaceOrigin.sol";

contract TestClient is IMessageRecipient {
    /// @notice Local chain Origin: used for sending messages
    address public immutable origin;

    /// @notice Local chain Destination: used for receiving messages
    address public immutable destination;

    event MessageReceived(uint32 origin, uint32 nonce, bytes32 sender, uint256 proofMaturity, bytes content);

    event MessageSent(uint32 destination, uint32 nonce, bytes32 sender, bytes32 recipient, bytes content);

    constructor(address origin_, address destination_) {
        origin = origin_;
        destination = destination_;
    }

    /// @inheritdoc IMessageRecipient
    function receiveBaseMessage(
        uint32 origin_,
        uint32 nonce,
        bytes32 sender,
        uint256 proofMaturity,
        bytes memory content
    ) external payable {
        require(msg.sender == destination, "TestClient: !destination");
        emit MessageReceived(origin_, nonce, sender, proofMaturity, content);
    }

    function sendMessage(uint32 destination_, address recipientAddress, uint32 optimisticSeconds, bytes memory content)
        external
    {
        bytes32 recipient = TypeCasts.addressToBytes32(recipientAddress);
        Tips tips = TipsLib.emptyTips();
        // TODO: figure out the logic for a message test
        Request request = RequestLib.encodeRequest(0, 0);
        (uint32 nonce,) = InterfaceOrigin(origin).sendBaseMessage(
            destination_, recipient, optimisticSeconds, Tips.unwrap(tips), Request.unwrap(request), content
        );
        emit MessageSent(destination_, nonce, TypeCasts.addressToBytes32(address(this)), recipient, content);
    }
}

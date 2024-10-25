// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import "../interfaces/IRandomiserCallbackV3.sol";
import "../interfaces/IAnyrand.sol";

contract MockRandomiser is IAnyrand {
    /// @notice Request price
    uint256 internal _requestPrice;
    /// @notice Next request ID
    uint256 public nextRequestId = 1;
    /// @notice Request ID to callback map
    mapping(uint256 => address) public requestIdToCallbackMap;
    /// @notice Authorised callers
    mapping(address => bool) public authorisedContracts;

    constructor() {
        authorisedContracts[msg.sender] = true;
        _requestPrice = 0.00001 ether;
    }

    /// @notice Sets the request price
    /// @param requestPrice_ New request price
    function setRequestPrice(uint256 requestPrice_) external {
        _requestPrice = requestPrice_;
    }

    /// @notice Gets the request price
    function getRequestPrice(uint256) external view returns (uint256, uint256) {
        return (_requestPrice, tx.gasprice);
    }

    /// @notice Request randomness
    /// @param deadline [UNUSED] Deadline
    /// @param callbackGasLimit [UNUSED] Callback gas limit
    function requestRandomness(
        uint256 deadline,
        uint256 callbackGasLimit
    ) external payable returns (uint256) {
        deadline;
        callbackGasLimit;
        uint256 requestId = nextRequestId++;
        requestIdToCallbackMap[requestId] = msg.sender;
        return requestId;
    }

    /// @notice Callback function used by VRF Coordinator (V2)
    /// @param requestId Request ID
    /// @param randomWord Random word
    function fulfillRandomness(uint256 requestId, uint256 randomWord) external {
        require(requestId < nextRequestId, "Request ID doesn't exist");
        address callbackContract = requestIdToCallbackMap[requestId];
        delete requestIdToCallbackMap[requestId];
        // ~7238 gas used before this line
        IRandomiserCallbackV3(callbackContract).receiveRandomness(
            requestId,
            randomWord
        );
    }

    function getRequestState(
        uint256 requestId
    ) external view returns (RequestState) {
        if (requestIdToCallbackMap[requestId] == address(0)) {
            return RequestState.Nonexistent;
        } else if (requestIdToCallbackMap[requestId] != address(0)) {
            return RequestState.Pending;
        } else {
            return RequestState.Fulfilled;
        }
    }
}

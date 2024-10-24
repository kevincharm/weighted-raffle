// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {SortitionSumTree} from "../lib/SortitionSumTree.sol";

contract SortitionSumTreeConsumer {
    using SortitionSumTree for SortitionSumTree.SST;

    SortitionSumTree.SST internal tree;
    uint256 public immutable K;

    /// @param K_ Number of children per node in the SST
    constructor(uint256 K_) {
        K = K_;
        tree.init(K_);
    }

    /// @notice Set (upsert) the value at key
    /// @param key Key to set
    /// @param value Value to set
    function set(bytes32 key, uint256 value) external {
        tree.set(value, key);
    }

    /// @notice Get a batch of leaves from the SST
    /// @param cursor Starting index of the batch
    /// @param count Number of leaves to retrieve
    function getLeaves(
        uint256 cursor,
        uint256 count
    )
        external
        view
        returns (uint256 startIndex, uint256[] memory values, bool hasMore)
    {
        return tree.queryLeafs(cursor, count);
    }
}

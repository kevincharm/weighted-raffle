// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {SortitionSumTree} from "../lib/SortitionSumTree.sol";
import {Pseudorandom} from "../lib/Pseudorandom.sol";
import {Maffs} from "../lib/Maffs.sol";

/// @notice Harness for testing the SortitionSumTree lib
contract SortitionSumTreeConsumer {
    using SortitionSumTree for SortitionSumTree.SST;

    /// @notice Tree
    SortitionSumTree.SST internal tree;
    /// @notice Number of children per node in the SST
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

    /// @notice Batch upsert
    function setBatch(bytes32[] memory keys, uint256[] memory values) external {
        for (uint256 i; i < keys.length; ++i) {
            tree.set(values[i], keys[i]);
        }
    }

    /// @notice Remove a key, i.e. set its value to 0
    /// @param key Key to remove
    function remove(bytes32 key) external {
        tree.set(0, key);
    }

    function removeBatch(bytes32[] memory keys) external {
        for (uint256 i; i < keys.length; ++i) {
            tree.set(0, keys[i]);
        }
    }

    /// @notice Draw a random leaf from the SST
    /// @param drawnNumber The drawn number. Ensure this is a uniform random
    ///     number in the range of [0, totalWeight).
    function draw(
        uint256 drawnNumber
    ) external view returns (bytes32 key, uint256 gasUsed) {
        gasUsed = gasleft();
        key = tree.draw(drawnNumber);
        gasUsed -= gasleft();
        return (key, gasUsed);
    }

    /// @notice Draw a random leaf from the SST using a uniform random number
    ///     generator.
    /// @param randomSeed The random seed to use
    function drawUniform(
        uint256 randomSeed
    ) external view returns (bytes32 key, uint256 gasUsed) {
        gasUsed = gasleft();
        uint256 drawnNumber = Pseudorandom.pick(
            randomSeed,
            tree.getTotalWeight()
        );
        key = tree.draw(drawnNumber);
        gasUsed -= gasleft();
        return (key, gasUsed);
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

    /// @notice Get ALL leaves
    function getAllLeaves() external view returns (uint256[] memory) {
        (, uint256[] memory values, ) = tree.queryLeafs(0, tree.nodes.length);
        return values;
    }

    /// @notice Get ALL keys
    function getAllKeys() external view returns (bytes32[] memory) {
        uint256 len = tree.nodes.length;
        bytes32[] memory keys = new bytes32[](len);
        for (uint256 i; i < len; ++i) {
            keys[i] = tree.nodeIndexesToIDs[i];
        }
        return keys;
    }

    /// @notice Get the value of a key
    /// @param key Key to get the value of
    function getValue(bytes32 key) external view returns (uint256) {
        return tree.stakeOf(key);
    }

    /// @notice Get total weight of tree
    function getTotalWeight() external view returns (uint256) {
        return tree.getTotalWeight();
    }

    /// @notice Estimate the gas required to draw and remove a leaf
    /// @notice Assumes a binary/2-ary SST
    /// @param n Number of nodes in the SST
    function estimateDrawGas2ary(uint256 n) external pure returns (uint256) {
        if (n == 0) return 0;
        uint256 clog = n == 1 ? 1 : Maffs.log2(n);

        uint256 drawGas; // O(k.log2(n))
        uint256 removeGas; // O(log2(n))
        if (n <= 16) {
            // real: 7877
            drawGas = 11815 * 2 * clog;
            // real: 56_340
            removeGas = 84510 * clog;
        } else {
            // real: 3525.05
            drawGas = 5288 * 2 * clog;
            // real: 10_821
            removeGas = 16_232 * clog;
        }
        return drawGas + removeGas;
    }
}

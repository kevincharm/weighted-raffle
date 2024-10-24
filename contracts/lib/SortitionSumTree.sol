// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

/// @custom:authors: [@epiqueras, @unknownunknown1]
/// @custom:reviewers: []
/// @custom:auditors: []
/// @custom:bounties: []
/// @custom:deployments: []

/// @title SortitionSumTree
/// @author Enrique Piqueras - <epiquerass@gmail.com>
/// @dev A factory of trees that keep track of staked values for sortition.
/// @notice Borrowed from Kleros v2 & slightly modified:
///     https://github.com/kleros/kleros-v2/blob/e0361dc772bdc441b9585a945ede9f1628db74ff/contracts/src/libraries/SortitionSumTreeF.sol
library SortitionSumTree {
    struct SST {
        /// @notice The maximum number of childs per node.
        uint256 K;
        /// @notice We use this to keep track of vacant positions in the tree
        /// after removing a leaf. This is for keeping the tree as balanced as
        /// possible without spending gas on moving nodes around.
        uint256[] stack;
        /// @notice The nodes of the tree.
        uint256[] nodes;
        /// @notice Two-way mapping of IDs to node indexes. Note that node
        /// index 0 is reserved for the root node, and means the ID does not
        /// have a node.
        mapping(bytes32 id => uint256 index) IDsToNodeIndexes;
        mapping(uint256 index => bytes32 id) nodeIndexesToIDs;
    }

    error SortitionSumTree__TreeAlreadyExists();
    error SortitionSumTree__KMustBeGreaterThanOne(uint256 k);

    /// @dev Initialise a SortitionSumTree
    /// @param _K The number of children each node in the tree should have.
    function init(SST storage tree, uint256 _K) internal {
        if (tree.K != 0) revert SortitionSumTree__TreeAlreadyExists();
        if (_K <= 1) revert SortitionSumTree__KMustBeGreaterThanOne(_K);
        tree.K = _K;
        tree.nodes.push(0);
    }

    /// @dev Set a value of a tree.
    /// @param _value The new value.
    /// @param _ID The ID of the value.
    /// `O(log_k(n))` where
    /// `k` is the maximum number of childs per node in the tree,
    ///  and `n` is the maximum number of nodes ever appended.
    function set(SST storage tree, uint256 _value, bytes32 _ID) internal {
        uint256 treeIndex = tree.IDsToNodeIndexes[_ID];

        if (treeIndex == 0) {
            // No existing node.
            if (_value != 0) {
                // Non zero value.
                // Append.
                // Add node.
                if (tree.stack.length == 0) {
                    // No vacant spots.
                    // Get the index and append the value.
                    treeIndex = tree.nodes.length;
                    tree.nodes.push(_value);

                    // Potentially append a new node and make the parent a sum node.
                    if (treeIndex != 1 && (treeIndex - 1) % tree.K == 0) {
                        // Is first child.
                        uint256 parentIndex = treeIndex / tree.K;
                        bytes32 parentID = tree.nodeIndexesToIDs[parentIndex];
                        uint256 newIndex = treeIndex + 1;
                        tree.nodes.push(tree.nodes[parentIndex]);
                        delete tree.nodeIndexesToIDs[parentIndex];
                        tree.IDsToNodeIndexes[parentID] = newIndex;
                        tree.nodeIndexesToIDs[newIndex] = parentID;
                    }
                } else {
                    // Some vacant spot.
                    // Pop the stack and append the value.
                    treeIndex = tree.stack[tree.stack.length - 1];
                    tree.stack.pop();
                    tree.nodes[treeIndex] = _value;
                }

                // Add label.
                tree.IDsToNodeIndexes[_ID] = treeIndex;
                tree.nodeIndexesToIDs[treeIndex] = _ID;

                updateParents(tree, treeIndex, true, _value);
            }
        } else {
            // Existing node.
            if (_value == 0) {
                // Zero value.
                // Remove.
                // Remember value and set to 0.
                uint256 value = tree.nodes[treeIndex];
                tree.nodes[treeIndex] = 0;

                // Push to stack.
                tree.stack.push(treeIndex);

                // Clear label.
                delete tree.IDsToNodeIndexes[_ID];
                delete tree.nodeIndexesToIDs[treeIndex];

                updateParents(tree, treeIndex, false, value);
            } else if (_value != tree.nodes[treeIndex]) {
                // New, non zero value.
                // Set.
                bool plusOrMinus = tree.nodes[treeIndex] <= _value;
                uint256 plusOrMinusValue = plusOrMinus
                    ? _value - tree.nodes[treeIndex]
                    : tree.nodes[treeIndex] - _value;
                tree.nodes[treeIndex] = _value;

                updateParents(tree, treeIndex, plusOrMinus, plusOrMinusValue);
            }
        }
    }

    /// @dev Query the leaves of a tree. Note that if `startIndex == 0`, the tree is empty and the root node will be returned.
    /// @param _cursor The pagination cursor.
    /// @param _count The number of items to return.
    /// @return startIndex The index at which leaves start.
    /// @return values The values of the returned leaves.
    /// @return hasMore Whether there are more for pagination.
    /// `O(n)` where
    /// `n` is the maximum number of nodes ever appended.
    function queryLeafs(
        SST storage tree,
        uint256 _cursor,
        uint256 _count
    )
        internal
        view
        returns (uint256 startIndex, uint256[] memory values, bool hasMore)
    {
        // Find the start index.
        for (uint256 i = 0; i < tree.nodes.length; i++) {
            if ((tree.K * i) + 1 >= tree.nodes.length) {
                startIndex = i;
                break;
            }
        }

        // Get the values.
        uint256 loopStartIndex = startIndex + _cursor;
        values = new uint256[](
            loopStartIndex + _count > tree.nodes.length
                ? tree.nodes.length - loopStartIndex
                : _count
        );
        uint256 valuesIndex = 0;
        for (uint256 j = loopStartIndex; j < tree.nodes.length; j++) {
            if (valuesIndex < _count) {
                values[valuesIndex] = tree.nodes[j];
                valuesIndex++;
            } else {
                hasMore = true;
                break;
            }
        }
    }

    /// @dev Draw an ID from a tree using a number. Note that this function reverts if the sum of all values in the tree is 0.
    /// @param _drawnNumber The drawn number.
    /// @return ID The drawn ID.
    /// `O(k * log_k(n))` where
    /// `k` is the maximum number of childs per node in the tree,
    ///  and `n` is the maximum number of nodes ever appended.
    function draw(
        SST storage tree,
        uint256 _drawnNumber
    ) internal view returns (bytes32 ID) {
        uint256 treeIndex = 0;
        uint256 currentDrawnNumber = _drawnNumber % tree.nodes[0];

        while (
            (tree.K * treeIndex) + 1 < tree.nodes.length // While it still has children.
        )
            for (uint256 i = 1; i <= tree.K; i++) {
                // Loop over children.
                uint256 nodeIndex = (tree.K * treeIndex) + i;
                uint256 nodeValue = tree.nodes[nodeIndex];

                if (currentDrawnNumber >= nodeValue)
                    currentDrawnNumber -= nodeValue; // Go to the next child.
                else {
                    // Pick this child.
                    treeIndex = nodeIndex;
                    break;
                }
            }

        ID = tree.nodeIndexesToIDs[treeIndex];
    }

    /// @dev Gets a specified ID's associated value.
    /// @param _ID The ID of the value.
    /// @return value The associated value.
    function stakeOf(
        SST storage tree,
        bytes32 _ID
    ) internal view returns (uint256 value) {
        uint256 treeIndex = tree.IDsToNodeIndexes[_ID];

        if (treeIndex == 0) value = 0;
        else value = tree.nodes[treeIndex];
    }

    /// Private

    /// @dev Update all the parents of a node.
    /// @param _treeIndex The index of the node to start from.
    /// @param _plusOrMinus Wether to add (true) or substract (false).
    /// @param _value The value to add or substract.
    /// `O(log_k(n))` where
    /// `k` is the maximum number of childs per node in the tree,
    ///  and `n` is the maximum number of nodes ever appended.
    function updateParents(
        SST storage tree,
        uint256 _treeIndex,
        bool _plusOrMinus,
        uint256 _value
    ) private {
        uint256 parentIndex = _treeIndex;
        while (parentIndex != 0) {
            parentIndex = (parentIndex - 1) / tree.K;
            tree.nodes[parentIndex] = _plusOrMinus
                ? tree.nodes[parentIndex] + _value
                : tree.nodes[parentIndex] - _value;
        }
    }
}

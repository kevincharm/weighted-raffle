// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {FeistelShuffleOptimised} from "solshuffle/contracts/FeistelShuffleOptimised.sol";

/// @title WeightedRaffle
/// @notice Draft weighted raffle implementation
contract WeightedRaffle {
    struct Entry {
        /// @notice Owner of the ticket
        address beneficiary;
        /// @notice Beginning of range that this entry covers (inclusive)
        uint256 start;
        /// @notice End of range (exclusive)
        uint256 end;
    }

    /// @notice Raffle entries
    Entry[] public entries;
    /// @notice Random seed
    uint256 public randomSeed;

    /// @notice Add a raffle entry. This function enforces that consecutive
    ///     entries cover adjacent ranges.
    function addEntry(address beneficiary, uint256 weight) public {
        require(beneficiary != address(0), "Beneficiary must exist");
        require(weight > 0, "Weight must be nonzero");

        if (entries.length == 0) {
            entries.push(
                Entry({beneficiary: beneficiary, start: 0, end: weight})
            );
        } else {
            Entry storage lastEntry = entries[entries.length - 1];
            entries.push(
                Entry({
                    beneficiary: beneficiary,
                    start: lastEntry.end,
                    end: lastEntry.end + weight
                })
            );
        }
    }

    /// @notice Placeholder for VRF callback
    function draw(uint256 randomSeed_) public {
        require(randomSeed == 0, "Raffle already finalised");
        randomSeed = randomSeed_;
    }

    /// @notice Compute winner
    function getWinner() public view returns (address) {
        require(randomSeed != 0, "Raffle not finalised");

        Entry memory lastEntry = entries[entries.length - 1];
        uint256 index = FeistelShuffleOptimised.deshuffle(
            0 /** 1st place */,
            lastEntry.end,
            randomSeed,
            4
        );
        // binsearch to find the range that index is covered by
        uint256 l = 0;
        uint256 r = entries.length - 1;
        while (l <= r) {
            uint256 m = (l + r) / 2;
            Entry memory entry = entries[m];
            if (entry.start <= index && index < entry.end) {
                return entry.beneficiary;
            } else if (entry.start > index) {
                r = m - 1;
            } else {
                l = m + 1;
            }
        }
        revert("Invariant violation: index out of range");
    }
}

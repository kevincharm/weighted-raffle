// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "hardhat/console.sol";

/// https://utopia.duth.gr/%7Epefraimi/research/data/2007EncOfAlg.pdf

/// @title WeightedRaffle
/// @notice Draft weighted raffle implementation
contract WRS {
    using EnumerableSet for EnumerableSet.AddressSet;

    struct Entry {
        /// @notice Owner of the ticket
        address beneficiary;
        /// @notice Weight in the range [0, 2^96)
        uint96 weight;
    }

    /// @notice Raffle entries
    Entry[] public entries;
    /// @notice Random seed
    uint256 public randomSeed;
    /// @notice Number of winners to be drawn
    uint256 public numWinners;
    /// @notice Drawn winners
    EnumerableSet.AddressSet internal winners;

    constructor(uint256 numWinners_) {
        require(numWinners_ > 0, "Number of winners must be nonzero");
        numWinners = numWinners_;
    }

    /// @notice Add a raffle entry. This function enforces that consecutive
    ///     entries cover adjacent ranges.
    function addEntry(address beneficiary, uint96 weight) public {
        require(beneficiary != address(0), "Beneficiary must exist");
        require(weight > 0, "Weight must be nonzero");
        entries.push(Entry({beneficiary: beneficiary, weight: weight}));
    }

    function fulfillRandomWords(uint256 randomSeed_) public {
        require(randomSeed == 0, "Raffle already finalised");
        randomSeed = randomSeed_;
    }

    /// @notice Placeholder for VRF callback
    function draw(uint256[] calldata indices) public {
        require(randomSeed != 0, "Raffle not yet finalised");
        uint256 randomSeed_ = randomSeed;

        uint256 V = entries.length;
        require(indices.length == V, "Invalid indices length");

        uint256 W = numWinners;
        uint256 lastRank = type(uint256).max;
        bool[] memory touched = new bool[](V);
        for (uint256 i; i < V; ++i) {
            require(!touched[indices[i]], "Duplicate index");
            touched[indices[i]] = true;

            Entry memory entry = entries[indices[i]];
            uint256 k = uint256(
                keccak256(abi.encode(randomSeed_, indices[i]))
            ) / uint256(entry.weight);
            require(lastRank > k, "Not sorted");
            lastRank = k;
            if (i < W) {
                winners.add(entry.beneficiary);
            } // we don't just break because we need to check duplicate indices
        }
    }
}

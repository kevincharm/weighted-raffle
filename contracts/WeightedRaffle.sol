// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FeistelShuffleOptimised} from "solshuffle/contracts/FeistelShuffleOptimised.sol";

/// @title WeightedRaffle
/// @notice Draft weighted raffle implementation
contract WeightedRaffle is Initializable, OwnableUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

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
    /// @notice Drawn winners
    EnumerableSet.AddressSet internal winners;

    constructor() {
        _disableInitializers();
    }

    function init(address owner_) public initializer {
        __Ownable_init(owner_);
    }

    /// @notice Helper for batch-adding entries
    /// @param beneficiaries List of beneficiaries
    /// @param weights List of weights
    function addEntries(
        address[] calldata beneficiaries,
        uint256[] calldata weights
    ) external onlyOwner {
        require(beneficiaries.length == weights.length, "Lengths mismatch");
        for (uint256 i; i < beneficiaries.length; ++i) {
            _addEntry(beneficiaries[i], weights[i]);
        }
    }

    /// @notice Add a raffle entry. This function enforces that consecutive
    ///     entries cover adjacent ranges.
    function addEntry(address beneficiary, uint256 weight) external onlyOwner {
        _addEntry(beneficiary, weight);
    }

    /// @notice Add a raffle entry. This function enforces that consecutive
    ///     entries cover adjacent ranges.
    function _addEntry(address beneficiary, uint256 weight) internal {
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
    function draw(uint256 randomSeed_, uint256 numWinners) public onlyOwner {
        require(randomSeed == 0, "Raffle already finalised");
        randomSeed = randomSeed_;

        uint256 i;
        for (uint256 n; n < numWinners; ++n) {
            address winner;
            do {
                winner = computeWinner(i++);
            } while (winners.contains(winner));
            winners.add(winner);
        }
    }

    /// @notice Fetch nth winner
    /// @param n nth place winner to fetch (0-indexed)
    function getWinner(uint256 n) public view returns (address) {
        require(randomSeed != 0, "Raffle not finalised");
        // Missing: n range check
        return winners.at(n);
    }

    /// @notice Compute winner
    /// @param n nth place winner to compute (0-indexed)
    ///     e.g. Set n=0 to compute 1st place winner
    function computeWinner(uint256 n) internal view returns (address winner) {
        Entry memory lastEntry = entries[entries.length - 1];
        uint256 index = FeistelShuffleOptimised.deshuffle(
            n,
            lastEntry.end,
            randomSeed,
            12
        );
        // binsearch to find the range that index is covered by
        uint256 l = 0;
        uint256 r = entries.length - 1;

        while (l <= r) {
            uint256 m = (l + r) / 2;
            Entry memory entry = entries[m];
            if (entry.start <= index && index < entry.end) {
                winner = entry.beneficiary;
                break;
            } else if (entry.start > index) {
                r = m - 1;
            } else {
                l = m + 1;
            }
        }
        require(
            winner != address(0),
            "Invariant violation: index out of range"
        );
    }
}

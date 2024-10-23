// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FeistelShuffleOptimised} from "solshuffle/contracts/FeistelShuffleOptimised.sol";
import {IRandomiserCallbackV3} from "./interfaces/IRandomiserCallbackV3.sol";
import {IAnyrand} from "./interfaces/IAnyrand.sol";

/// @title WeightedRaffle
/// @author Kevin Charm <kevin@frogworks.io>
/// @notice Weighted raffle implementation for Octant Sweepstakes
contract WeightedRaffle is
    Initializable,
    OwnableUpgradeable,
    IRandomiserCallbackV3
{
    using EnumerableSet for EnumerableSet.AddressSet;

    enum RaffleState {
        /// @notice Uninitialised
        Uninitialised,
        /// @notice Ready to receive entries
        Ready,
        /// @notice Randomness requested, no longer accepting entries
        RandomnessRequested,
        /// @notice Finalised, winners have been drawn
        Finalised
    }

    struct Entry {
        /// @notice Owner of the ticket
        address beneficiary;
        /// @notice Beginning of range that this entry covers (inclusive)
        uint256 start;
        /// @notice End of range (exclusive)
        uint256 end;
    }

    /// @notice Randomiser contract
    address public randomiser;
    /// @notice Raffle state
    RaffleState public raffleState;
    /// @notice Raffle entries
    Entry[] public entries;
    /// @notice Number of winners to draw
    uint256 public numWinners;
    /// @notice VRF request ID
    uint256 public requestId;
    /// @notice Drawn winners
    EnumerableSet.AddressSet internal winners;

    event RaffleEntryAdded(
        address indexed beneficiary,
        uint256 weight,
        uint256 start,
        uint256 end
    );
    event RaffleDrawInitiated(uint256 requestId);
    event RaffleFinalised(uint256 randomSeed);

    /// NB: Use this contract behind a proxy
    constructor() {
        _disableInitializers();
    }

    /// @notice Receive ETH; used to cover VRF request/callback gas cost
    receive() external payable {}

    /// @notice Withdraw ETH from the contract
    function withdrawETH() public onlyOwner {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Withdrawal failed");
    }

    /// @notice Proxy initialiser
    /// @param owner_ Owner of the contract
    /// @param randomiser_ Randomiser contract
    function init(address owner_, address randomiser_) public initializer {
        __Ownable_init(owner_);
        randomiser = randomiser_;
        raffleState = RaffleState.Ready;
    }

    /// @notice Guard - only allow execution in a certain state
    modifier onlyInState(RaffleState state) {
        require(raffleState == state, "Invalid state");
        _;
    }

    /// @notice Helper for batch-adding entries
    /// @dev NB: Privileged
    /// @param beneficiaries List of beneficiaries
    /// @param weights List of weights
    function addEntries(
        address[] calldata beneficiaries,
        uint256[] calldata weights
    ) public onlyInState(RaffleState.Ready) onlyOwner {
        require(beneficiaries.length == weights.length, "Lengths mismatch");
        for (uint256 i; i < beneficiaries.length; ++i) {
            _addEntry(beneficiaries[i], weights[i]);
        }
    }

    /// @notice Add a single raffle entry.
    /// @dev NB: Privileged
    /// @param beneficiary Beneficiary
    /// @param weight Weight
    function addEntry(
        address beneficiary,
        uint256 weight
    ) public onlyInState(RaffleState.Ready) onlyOwner {
        _addEntry(beneficiary, weight);
    }

    /// @notice Add a raffle entry. This function enforces that consecutive
    ///     entries cover adjacent ranges.
    /// @param beneficiary Beneficiary
    /// @param weight Weight
    function _addEntry(address beneficiary, uint256 weight) internal {
        require(beneficiary != address(0), "Beneficiary must exist");
        require(weight > 0, "Weight must be nonzero");

        uint256 start;
        uint256 end;
        if (entries.length == 0) {
            end = weight;
        } else {
            Entry storage lastEntry = entries[entries.length - 1];
            start = lastEntry.end;
            end = lastEntry.end + weight;
        }
        entries.push(Entry({beneficiary: beneficiary, start: start, end: end}));
        emit RaffleEntryAdded(beneficiary, weight, start, end);
    }

    /// @notice Estimate callback gas
    /// @param numWinners_ Number of winners to draw
    function getEstimatedCallbackGas(
        uint256 numWinners_
    ) public pure returns (uint256) {
        return 100_000 * numWinners_;
    }

    /// @notice Estimate VRF request price
    /// @notice NB: tx.gasprice must be set when calling this function
    ///     statically offchain!
    /// @param numWinners_ Number of winners to draw
    function getRequestPrice(
        uint256 numWinners_
    ) public view returns (uint256) {
        (uint256 requestPrice, ) = IAnyrand(randomiser).getRequestPrice(
            getEstimatedCallbackGas(numWinners_)
        );
        return requestPrice;
    }

    /// @notice Initiate the raffle draw, requesting random words from VRF.
    /// @param numWinners_ Number of winners to draw
    function draw(
        uint256 numWinners_
    ) public onlyInState(RaffleState.Ready) onlyOwner {
        // Record number of winners we want to draw; we'll need it in the VRF
        // callback
        numWinners = numWinners_;

        // Compute VRF request price
        uint256 callbackGasLimit = getEstimatedCallbackGas(numWinners_);
        uint256 requestPrice = getRequestPrice(numWinners_);
        require(address(this).balance >= requestPrice, "Insufficient payment");

        // Make VRF request & record the expected requestId in the callback
        raffleState = RaffleState.RandomnessRequested;
        requestId = IAnyrand(randomiser).requestRandomness{value: requestPrice}(
            block.timestamp + 30 seconds,
            callbackGasLimit
        );

        emit RaffleDrawInitiated(requestId);
    }

    /// @inheritdoc IRandomiserCallbackV3
    function receiveRandomness(
        uint256 requestId_,
        uint256 randomWord
    ) external onlyInState(RaffleState.RandomnessRequested) {
        require(msg.sender == randomiser, "Unexpected VRF fulfiller");
        require(requestId_ == requestId, "Unexpected requestId");

        uint256 i;
        for (uint256 n; n < numWinners; ++n) {
            address winner;
            do {
                winner = computeWinner(randomWord, i++);
            } while (winners.contains(winner));
            winners.add(winner);
        }

        raffleState = RaffleState.Finalised;
        emit RaffleFinalised(randomWord);
    }

    /// @notice Compute winner
    /// @param randomSeed Random seed
    /// @param n nth place winner to compute (0-indexed)
    ///     e.g. Set n=0 to compute 1st place winner
    function computeWinner(
        uint256 randomSeed,
        uint256 n
    ) internal view returns (address winner) {
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
        assert(winner != address(0)); // Invariant violation: index out of range
    }

    /// @notice Fetch nth winner
    /// @param n nth place winner to fetch (0-indexed)
    function getWinner(
        uint256 n
    ) public view onlyInState(RaffleState.Finalised) returns (address) {
        // Missing: n range check
        return winners.at(n);
    }
}

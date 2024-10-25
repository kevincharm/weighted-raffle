// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

import {WeightedRaffle} from "../WeightedRaffle.sol";

contract WeightedRaffleHarness is WeightedRaffle {
    function setState(RaffleState state) public {
        raffleState = state;
    }
}

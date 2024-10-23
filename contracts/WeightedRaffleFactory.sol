// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {WeightedRaffle} from "./WeightedRaffle.sol";

/// @notice WeightedRaffleFactory
/// @author Kevin Charm <kevin@frogworks.io>
/// @notice Factory for deploying weighted raffles
contract WeightedRaffleFactory is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Raffle master copy
    address public raffleMasterCopy;
    /// @notice Randomiser (Anyrand) contract address
    address public randomiser;

    event RaffleDeployed(
        address indexed raffle,
        address indexed raffleMasterCopy,
        address indexed deployer
    );
    event RaffleMasterCopySet(address indexed raffleMasterCopy);
    event RandomiserSet(address indexed randomiser);

    function init(
        address raffleMasterCopy_,
        address randomiser_
    ) public initializer {
        __UUPSUpgradeable_init(); // noop
        __Ownable_init(msg.sender);
        raffleMasterCopy = raffleMasterCopy_;
        randomiser = randomiser_;
    }

    /// @notice Authorise an upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    /// @notice Set the raffle master copy
    function setRaffleMasterCopy(address raffleMasterCopy_) public onlyOwner {
        raffleMasterCopy = raffleMasterCopy_;
        emit RaffleMasterCopySet(raffleMasterCopy_);
    }

    /// @notice Set the randomiser
    /// @param randomiser_ Randomiser (Anyrand) contract address
    function setRandomiser(address randomiser_) public onlyOwner {
        randomiser = randomiser_;
        emit RandomiserSet(randomiser_);
    }

    /// @notice Deploy a new raffle
    function deployRaffle() public returns (address) {
        address raffle = Clones.clone(raffleMasterCopy);
        WeightedRaffle(payable(raffle)).init(msg.sender, randomiser);
        emit RaffleDeployed(raffle, raffleMasterCopy, msg.sender);
        return raffle;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {WeightedRaffle} from "./WeightedRaffle.sol";

/// @notice WeightedRaffleFactory
contract WeightedRaffleFactory is UUPSUpgradeable, OwnableUpgradeable {
    /// @notice Raffle master copy
    address public raffleMasterCopy;

    event RaffleDeployed(
        address indexed raffle,
        address indexed raffleMasterCopy,
        address indexed deployer
    );

    function init(address raffleMasterCopy_) public initializer {
        __UUPSUpgradeable_init(); // noop
        __Ownable_init(msg.sender);
        raffleMasterCopy = raffleMasterCopy_;
    }

    /// @notice Authorise an upgrade
    function _authorizeUpgrade(
        address newImplementation
    ) internal virtual override onlyOwner {}

    /// @notice Set the raffle master copy
    function setRaffleMasterCopy(address raffleMasterCopy_) public onlyOwner {
        raffleMasterCopy = raffleMasterCopy_;
    }

    /// @notice Deploy a new raffle
    function deployRaffle() public returns (address) {
        address raffle = Clones.clone(raffleMasterCopy);
        WeightedRaffle(raffle).init(msg.sender);
        emit RaffleDeployed(raffle, raffleMasterCopy, msg.sender);
        return raffle;
    }
}

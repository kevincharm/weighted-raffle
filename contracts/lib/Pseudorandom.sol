// SPDX-License-Identifier: MIT
pragma solidity ^0.8;

/// @title Pseudorandom
/// @author Kevin Charm <kevin@frogworks.io>
/// @notice Pseudorandom. Not to be confused with the cat known as pseudotheos.
library Pseudorandom {
    uint256 private constant _UINT256_MAX = type(uint256).max;

    /// @notice Derive a pseudorandom number from a seed using bytes
    /// @param seed The input to derive from
    /// @return output keccak256(seed)
    function derive(bytes memory seed) internal pure returns (uint256 output) {
        assembly {
            let len := mload(seed)
            output := keccak256(add(seed, 0x20), len)
        }
    }

    /// @notice Derive a pseudorandom number from a seed using u256
    /// @param seed The input to derive from
    /// @return output keccak256(seed)
    function derive(uint256 seed) internal pure returns (uint256 output) {
        assembly {
            mstore(0x00, seed)
            output := keccak256(0x00, 0x20)
        }
    }

    /// @notice Derive a uniform random number in the range [0, max) from seed
    ///     without modulo bias.
    /// @param seed The input to derive from
    /// @param max The upper bound of the range
    /// @return A pseudorandom number in the range [0, max)
    function pick(uint256 seed, uint256 max) internal pure returns (uint256) {
        // modulo reduction of _UINT256_MAX by max
        uint256 ceiling = _UINT256_MAX - (_UINT256_MAX % max);
        uint256 candidate;
        do {
            candidate = derive(seed);
        } while (candidate >= ceiling);
        return candidate % max;
    }
}

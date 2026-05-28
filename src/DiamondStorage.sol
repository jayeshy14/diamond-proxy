// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title DiamondStorage: EIP-7201 namespaced storage for the Diamond proxy
/// @notice Provides a storage layout struct at a fixed slot to avoid collisions with facet storage
library DiamondStorage {
    /// @custom:storage-location erc7201:diamond.proxy.storage
    struct Layout {
        address owner;
        address pendingOwner;
        mapping(bytes4 => address) selectorToFacet;
        mapping(address => bytes4[]) facetSelectors;
        address[] facetAddresses;
        mapping(address => bool) isFacet;
        mapping(bytes4 => bool) supportedInterfaces;
        mapping(bytes4 => bool) isImmutableSelector;
    }

    // keccak256(abi.encode(uint256(keccak256("diamond.proxy.storage")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant STORAGE_SLOT = 0x3ba7105978bceda33a138e0eb0ea05e594e835c82d227a70af234cb063cc5100;

    /// @notice Returns the storage layout struct at the namespaced slot
    /// @return $ Storage pointer to the Layout struct
    function getLayout() internal pure returns (Layout storage $) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            $.slot := slot
        }
    }
}

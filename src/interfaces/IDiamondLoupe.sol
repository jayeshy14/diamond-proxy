// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDiamondLoupe: EIP-2535 Diamond Loupe Interface
/// @notice Introspection functions for querying facet-to-selector mappings
interface IDiamondLoupe {
    /// @param facetAddress Address of the facet
    /// @param functionSelectors Selectors routed to this facet
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Returns all facets and their selectors
    /// @return facets_ Array of Facet structs
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Returns all selectors for a given facet
    /// @param facet Address of the facet
    /// @return functionSelectors_ Array of 4-byte selectors
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory functionSelectors_);

    /// @notice Returns all facet addresses used by the Diamond
    /// @return facetAddresses_ Array of facet addresses
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /// @notice Returns the facet that handles a given selector
    /// @param functionSelector The 4-byte selector to query
    /// @return facetAddress_ The facet address (address(0) if not found)
    function facetAddress(bytes4 functionSelector) external view returns (address facetAddress_);
}

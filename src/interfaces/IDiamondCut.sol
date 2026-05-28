// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IDiamondCut: EIP-2535 Diamond Cut Interface
/// @notice Add, replace, or remove facet selectors on a Diamond proxy
interface IDiamondCut {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    /// @param facetAddress Address of the facet contract (ignored for Remove)
    /// @param action Whether to Add, Replace, or Remove the selectors
    /// @param functionSelectors Array of 4-byte selectors to modify
    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Emitted after a successful diamond cut
    /// @param diamondCut Array of cuts that were applied
    /// @param init Address delegatecalled for initialization (address(0) if none)
    /// @param data Calldata passed to init
    event DiamondCut(FacetCut[] diamondCut, address init, bytes data);

    /// @notice Add, replace, or remove facet selectors and optionally run an initializer
    /// @param cuts Array of FacetCut structs describing the mutations
    /// @param init Contract to delegatecall after applying cuts (address(0) to skip)
    /// @param data Calldata for the init delegatecall
    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external;
}

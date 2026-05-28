// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Diamond} from "../../src/Diamond.sol";
import {IDiamondCut} from "../../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/interfaces/IDiamondLoupe.sol";
import {IOwnership} from "../../src/interfaces/IOwnership.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {MockFacet} from "./MockFacet.sol";

/// @notice Echidna harness for Diamond invariants. The harness IS the owner.
contract DiamondEchidna {
    Diamond internal diamond;
    MockFacet internal facetA;
    MockFacet internal facetB;
    MockFacet internal facetC;

    // Pool of selectors echidna can pick from
    bytes4[8] internal pool;

    // Track which selectors have been added so we can build the "expected"
    // invariant state cheaply for echidna_loupe_consistent.
    mapping(bytes4 => address) internal expected;

    bytes4[11] internal immutableSelectors;

    constructor() {
        diamond = new Diamond(address(this));
        facetA = new MockFacet();
        facetB = new MockFacet();
        facetC = new MockFacet();

        pool[0] = MockFacet.foo.selector;
        pool[1] = MockFacet.bar.selector;
        pool[2] = MockFacet.baz.selector;
        pool[3] = MockFacet.qux.selector;
        pool[4] = MockFacet.quux.selector;
        pool[5] = MockFacet.corge.selector;
        pool[6] = MockFacet.grault.selector;
        pool[7] = MockFacet.garply.selector;

        immutableSelectors[0] = IDiamondCut.diamondCut.selector;
        immutableSelectors[1] = IDiamondLoupe.facets.selector;
        immutableSelectors[2] = IDiamondLoupe.facetFunctionSelectors.selector;
        immutableSelectors[3] = IDiamondLoupe.facetAddresses.selector;
        immutableSelectors[4] = IDiamondLoupe.facetAddress.selector;
        immutableSelectors[5] = IERC165.supportsInterface.selector;
        immutableSelectors[6] = IOwnership.transferOwnership.selector;
        immutableSelectors[7] = IOwnership.acceptOwnership.selector;
        immutableSelectors[8] = IOwnership.cancelOwnershipTransfer.selector;
        immutableSelectors[9] = IOwnership.owner.selector;
        immutableSelectors[10] = IOwnership.pendingOwner.selector;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    function _facet(uint8 which) internal view returns (address) {
        which = which % 3;
        if (which == 0) return address(facetA);
        if (which == 1) return address(facetB);
        return address(facetC);
    }

    function _selector(uint8 idx) internal view returns (bytes4) {
        return pool[idx % uint8(pool.length)];
    }

    // ─── Actions ──────────────────────────────────────────────────────────────

    function addSelector(uint8 selIdx, uint8 facetIdx) public {
        bytes4 sel = _selector(selIdx);
        address f = _facet(facetIdx);

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: f,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: sels
        });

        try diamond.diamondCut(cuts, address(0), "") {
            expected[sel] = f;
        } catch {
            // Expected to revert: duplicate selector, immutable selector, etc.
        }
    }

    function replaceSelector(uint8 selIdx, uint8 facetIdx) public {
        bytes4 sel = _selector(selIdx);
        address f = _facet(facetIdx);

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: f,
            action: IDiamondCut.FacetCutAction.Replace,
            functionSelectors: sels
        });

        try diamond.diamondCut(cuts, address(0), "") {
            expected[sel] = f;
        } catch {}
    }

    function removeSelector(uint8 selIdx) public {
        bytes4 sel = _selector(selIdx);

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: address(0),
            action: IDiamondCut.FacetCutAction.Remove,
            functionSelectors: sels
        });

        try diamond.diamondCut(cuts, address(0), "") {
            expected[sel] = address(0);
        } catch {}
    }

    // Try to cut an immutable selector — must always revert.
    function attemptImmutableCut(uint8 immIdx, uint8 action, uint8 facetIdx) public {
        bytes4 sel = immutableSelectors[immIdx % uint8(immutableSelectors.length)];
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;

        IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({
            facetAddress: _facet(facetIdx),
            action: IDiamondCut.FacetCutAction(action % 3),
            functionSelectors: sels
        });

        try diamond.diamondCut(cuts, address(0), "") {
            // If we land here the immutable-selector guard was bypassed.
            // echidna_immutable_selectors_intact will catch the state damage.
        } catch {}
    }

    // ─── Invariants ───────────────────────────────────────────────────────────

    /// @dev Harness is constructed as owner; only acceptOwnership can change it,
    /// and no test action ever sets a pendingOwner, so the owner must stay fixed.
    function echidna_owner_immutable() public view returns (bool) {
        return diamond.owner() == address(this) && diamond.pendingOwner() == address(0);
    }

    /// @dev Every selector returned by the loupe must resolve to the matching facet.
    function echidna_loupe_consistent() public view returns (bool) {
        IDiamondLoupe.Facet[] memory fs = diamond.facets();
        for (uint256 i = 0; i < fs.length; i++) {
            address f = fs[i].facetAddress;
            bytes4[] memory sels = fs[i].functionSelectors;
            if (sels.length == 0) return false; // empty facets must be cleaned up
            for (uint256 j = 0; j < sels.length; j++) {
                if (diamond.facetAddress(sels[j]) != f) return false;
            }
        }
        return true;
    }

    /// @dev Pool-tracked expected state matches actual diamond state.
    function echidna_expected_mapping_matches() public view returns (bool) {
        for (uint256 i = 0; i < pool.length; i++) {
            bytes4 s = pool[i];
            if (diamond.facetAddress(s) != expected[s]) return false;
        }
        return true;
    }

    /// @dev Immutable selectors are always mapped to the diamond itself.
    function echidna_immutable_selectors_intact() public view returns (bool) {
        address self = address(diamond);
        for (uint256 i = 0; i < immutableSelectors.length; i++) {
            if (diamond.facetAddress(immutableSelectors[i]) != self) return false;
        }
        return true;
    }

    /// @dev supportsInterface for the four core interfaces stays true.
    function echidna_supports_core_interfaces() public view returns (bool) {
        return diamond.supportsInterface(type(IERC165).interfaceId)
            && diamond.supportsInterface(type(IDiamondCut).interfaceId)
            && diamond.supportsInterface(type(IDiamondLoupe).interfaceId)
            && diamond.supportsInterface(type(IOwnership).interfaceId);
    }
}

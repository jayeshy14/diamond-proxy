// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "./interfaces/IDiamondLoupe.sol";
import {IOwnership} from "./interfaces/IOwnership.sol";
import {DiamondStorage} from "./DiamondStorage.sol";

/// @title Diamond: Single contract EIP-2535 Diamond proxy
/// @notice Immutable core with upgradeable facets via selector based routing
/// @dev Inherits OZ Proxy for delegatecall routing; core selectors (cut, loupe, ownership) cannot be replaced or removed
contract Diamond is Proxy, IDiamondCut, IDiamondLoupe, IOwnership, IERC165 {
    error NotOwner();
    error ZeroAddress();
    error SelectorAlreadyExists(bytes4 selector);
    error SelectorNotFound(bytes4 selector);
    error FacetCannotBeZero();
    error FacetHasNoCode(address facet);
    error InvalidFacet();
    error NoSelectorsProvided();
    error ImmutableSelector(bytes4 selector);
    error InitFailed();
    error InitHasNoCode(address init);
    error NotPendingOwner();
    error InvalidAction();
    error InvalidSelector();

    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    function _checkOwner() private view {
        if (msg.sender != DiamondStorage.getLayout().owner) revert NotOwner();
    }

    /// @notice Deploy with an initial owner and register immutable selectors
    /// @param _owner Address of the initial Diamond owner
    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddress();
        DiamondStorage.Layout storage $ = DiamondStorage.getLayout();
        $.owner = _owner;
        $.supportedInterfaces[type(IERC165).interfaceId] = true;
        $.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        $.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        $.supportedInterfaces[type(IOwnership).interfaceId] = true;

        _registerImmutableSelectors($);
    }

    /// @inheritdoc IDiamondCut
    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external onlyOwner {
        DiamondStorage.Layout storage $ = DiamondStorage.getLayout();

        for (uint256 i; i < cuts.length; ++i) {
            FacetCut calldata cut = cuts[i];
            if (cut.functionSelectors.length == 0) revert NoSelectorsProvided();

            if (cut.action == FacetCutAction.Add) {
                _addFacet($, cut.facetAddress, cut.functionSelectors);
            } else if (cut.action == FacetCutAction.Replace) {
                _replaceFacet($, cut.facetAddress, cut.functionSelectors);
            } else if (cut.action == FacetCutAction.Remove) {
                _removeFacet($, cut.functionSelectors);
            } else {
                revert InvalidAction();
            }
        }

        if (init != address(0)) {
            if (init.code.length == 0) revert InitHasNoCode(init);
            (bool success, bytes memory returndata) = init.delegatecall(data);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        revert(add(32, returndata), mload(returndata))
                    }
                }
                revert InitFailed();
            }
        }

        emit DiamondCut(cuts, init, data);
    }

    /// @inheritdoc IDiamondLoupe
    function facets() external view returns (Facet[] memory result) {
        DiamondStorage.Layout storage $ = DiamondStorage.getLayout();
        uint256 count = $.facetAddresses.length;
        result = new Facet[](count);
        for (uint256 i; i < count; ++i) {
            address addr = $.facetAddresses[i];
            result[i] = Facet({facetAddress: addr, functionSelectors: $.facetSelectors[addr]});
        }
    }

    /// @inheritdoc IDiamondLoupe
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory) {
        return DiamondStorage.getLayout().facetSelectors[facet];
    }

    /// @inheritdoc IDiamondLoupe
    function facetAddresses() external view returns (address[] memory) {
        return DiamondStorage.getLayout().facetAddresses;
    }

    /// @inheritdoc IDiamondLoupe
    function facetAddress(bytes4 selector) external view returns (address) {
        return DiamondStorage.getLayout().selectorToFacet[selector];
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return DiamondStorage.getLayout().supportedInterfaces[interfaceId];
    }

    /// @inheritdoc IOwnership
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        DiamondStorage.Layout storage $ = DiamondStorage.getLayout();
        $.pendingOwner = newOwner;
        emit OwnershipTransferStarted($.owner, newOwner);
    }

    /// @inheritdoc IOwnership
    function acceptOwnership() external {
        DiamondStorage.Layout storage $ = DiamondStorage.getLayout();
        if (msg.sender != $.pendingOwner) revert NotPendingOwner();
        address oldOwner = $.owner;
        $.owner = msg.sender;
        $.pendingOwner = address(0);
        emit OwnershipTransferred(oldOwner, msg.sender);
    }

    /// @inheritdoc IOwnership
    function cancelOwnershipTransfer() external onlyOwner {
        DiamondStorage.Layout storage $ = DiamondStorage.getLayout();
        address previousPending = $.pendingOwner;
        $.pendingOwner = address(0);
        emit OwnershipTransferCanceled(previousPending);
    }

    /// @inheritdoc IOwnership
    function owner() external view returns (address) {
        return DiamondStorage.getLayout().owner;
    }

    /// @inheritdoc IOwnership
    function pendingOwner() external view returns (address) {
        return DiamondStorage.getLayout().pendingOwner;
    }

    receive() external payable {
        revert();
    }

    /// @dev Routes calls to the facet registered for msg.sig
    function _implementation() internal view override returns (address) {
        address facet = DiamondStorage.getLayout().selectorToFacet[msg.sig];
        if (facet == address(0)) revert SelectorNotFound(msg.sig);
        return facet;
    }

    /// @dev Registers all core selectors as immutable, mapped to address(this)
    function _registerImmutableSelectors(DiamondStorage.Layout storage $) private {
        address self = address(this);
        $.facetAddresses.push(self);
        $.isFacet[self] = true;

        bytes4[11] memory core = [
            IDiamondCut.diamondCut.selector,
            IDiamondLoupe.facets.selector,
            IDiamondLoupe.facetFunctionSelectors.selector,
            IDiamondLoupe.facetAddresses.selector,
            IDiamondLoupe.facetAddress.selector,
            IERC165.supportsInterface.selector,
            IOwnership.transferOwnership.selector,
            IOwnership.acceptOwnership.selector,
            IOwnership.cancelOwnershipTransfer.selector,
            IOwnership.owner.selector,
            IOwnership.pendingOwner.selector
        ];

        bytes4[] storage selectors = $.facetSelectors[self];
        for (uint256 i; i < core.length; ++i) {
            bytes4 sel = core[i];
            selectors.push(sel);
            $.selectorToFacet[sel] = self;
            $.isImmutableSelector[sel] = true;
        }
    }

    /// @dev Registers a new facet and maps selectors to it
    function _addFacet(DiamondStorage.Layout storage $, address facet, bytes4[] calldata selectors) private {
        if (facet == address(0)) revert FacetCannotBeZero();
        if (facet == address(this)) revert InvalidFacet();
        if (facet.code.length == 0) revert FacetHasNoCode(facet);

        if (!$.isFacet[facet]) {
            $.facetAddresses.push(facet);
            $.isFacet[facet] = true;
        }

        for (uint256 i; i < selectors.length; ++i) {
            bytes4 sel = selectors[i];
            if (sel == bytes4(0)) revert InvalidSelector();
            _ensureNotImmutable(sel);
            if ($.selectorToFacet[sel] != address(0)) revert SelectorAlreadyExists(sel);
            $.selectorToFacet[sel] = facet;
            $.facetSelectors[facet].push(sel);
        }
    }

    /// @dev Replaces selector mappings from old facet to new facet
    function _replaceFacet(DiamondStorage.Layout storage $, address facet, bytes4[] calldata selectors) private {
        if (facet == address(0)) revert FacetCannotBeZero();
        if (facet == address(this)) revert InvalidFacet();
        if (facet.code.length == 0) revert FacetHasNoCode(facet);

        if (!$.isFacet[facet]) {
            $.facetAddresses.push(facet);
            $.isFacet[facet] = true;
        }

        for (uint256 i; i < selectors.length; ++i) {
            bytes4 sel = selectors[i];
            if (sel == bytes4(0)) revert InvalidSelector();
            _ensureNotImmutable(sel);
            address oldFacet = $.selectorToFacet[sel];
            if (oldFacet == address(0)) revert SelectorNotFound(sel);
            if (oldFacet == facet) revert SelectorAlreadyExists(sel);

            _removeSelectorFromFacet($, oldFacet, sel);
            $.selectorToFacet[sel] = facet;
            $.facetSelectors[facet].push(sel);

            _cleanupFacetIfEmpty($, oldFacet);
        }
    }

    /// @dev Removes selectors and cleans up empty facets
    function _removeFacet(DiamondStorage.Layout storage $, bytes4[] calldata selectors) private {
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 sel = selectors[i];
            if (sel == bytes4(0)) revert InvalidSelector();
            _ensureNotImmutable(sel);
            address facet = $.selectorToFacet[sel];
            if (facet == address(0)) revert SelectorNotFound(sel);

            _removeSelectorFromFacet($, facet, sel);
            delete $.selectorToFacet[sel];

            _cleanupFacetIfEmpty($, facet);
        }
    }

    /// @dev Swap-and-pop removal of a selector from a facet's selector array
    function _removeSelectorFromFacet(DiamondStorage.Layout storage $, address facet, bytes4 sel) private {
        bytes4[] storage selectors = $.facetSelectors[facet];
        uint256 len = selectors.length;
        for (uint256 i; i < len; ++i) {
            if (selectors[i] == sel) {
                selectors[i] = selectors[len - 1];
                selectors.pop();
                return;
            }
        }
        revert SelectorNotFound(sel);
    }

    /// @dev Removes a facet from facetAddresses if it has no remaining selectors
    function _cleanupFacetIfEmpty(DiamondStorage.Layout storage $, address facet) private {
        if ($.facetSelectors[facet].length == 0) {
            $.isFacet[facet] = false;
            address[] storage addresses = $.facetAddresses;
            uint256 len = addresses.length;
            for (uint256 i; i < len; ++i) {
                if (addresses[i] == facet) {
                    addresses[i] = addresses[len - 1];
                    addresses.pop();
                    return;
                }
            }
        }
    }

    /// @dev Reverts if the selector belongs to an immutable core function
    function _ensureNotImmutable(bytes4 sel) private view {
        if (DiamondStorage.getLayout().isImmutableSelector[sel]) revert ImmutableSelector(sel);
    }
}

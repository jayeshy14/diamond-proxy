// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Diamond} from "../src/Diamond.sol";
import {IDiamondCut} from "../src/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/interfaces/IDiamondLoupe.sol";
import {IOwnership} from "../src/interfaces/IOwnership.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract FacetA {
    function a1() external pure returns (uint256) {
        return 0xa1;
    }

    function a2() external pure returns (uint256) {
        return 0xa2;
    }

    function a3() external pure returns (uint256) {
        return 0xa3;
    }
}

contract FacetB {
    function a1() external pure returns (uint256) {
        return 0xb1; // same selector as FacetA.a1
    }

    function b1() external pure returns (uint256) {
        return 0xbb1;
    }
}

contract GoodInit {
    event Initialized(uint256 marker);

    function init(uint256 marker) external {
        emit Initialized(marker);
    }
}

contract BadInit {
    error InitBoom(string reason);

    function blow() external pure {
        revert InitBoom("nope");
    }

    function silent() external pure {
        revert();
    }
}

contract DiamondTest is Test {
    Diamond internal d;
    FacetA internal fa;
    FacetB internal fb;

    address internal constant OWNER = address(0xA11CE);
    address internal constant ALICE = address(0xB0B);
    address internal constant BOB = address(0xC0DE);

    event DiamondCut(IDiamondCut.FacetCut[] diamondCut, address init, bytes data);
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferCanceled(address indexed previousPending);

    function setUp() public {
        d = new Diamond(OWNER);
        fa = new FacetA();
        fb = new FacetB();
    }

    // ───────── Helpers ──────────────────────────────────────────────────

    function _oneSelCut(address facet, IDiamondCut.FacetCutAction action, bytes4 sel)
        internal
        pure
        returns (IDiamondCut.FacetCut[] memory cuts)
    {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({facetAddress: facet, action: action, functionSelectors: sels});
    }

    function _multiSelCut(address facet, IDiamondCut.FacetCutAction action, bytes4[] memory sels)
        internal
        pure
        returns (IDiamondCut.FacetCut[] memory cuts)
    {
        cuts = new IDiamondCut.FacetCut[](1);
        cuts[0] = IDiamondCut.FacetCut({facetAddress: facet, action: action, functionSelectors: sels});
    }

    // ───────── Constructor ──────────────────────────────────────────────

    function test_constructor_setsOwner() public view {
        assertEq(d.owner(), OWNER);
        assertEq(d.pendingOwner(), address(0));
    }

    function test_constructor_revertsZeroOwner() public {
        vm.expectRevert(Diamond.ZeroAddress.selector);
        new Diamond(address(0));
    }

    function test_constructor_registersCoreInterfaces() public view {
        assertTrue(d.supportsInterface(type(IERC165).interfaceId));
        assertTrue(d.supportsInterface(type(IDiamondCut).interfaceId));
        assertTrue(d.supportsInterface(type(IDiamondLoupe).interfaceId));
        assertTrue(d.supportsInterface(type(IOwnership).interfaceId));
        assertFalse(d.supportsInterface(0xdeadbeef));
    }

    function test_constructor_registersImmutableCoreSelectors() public view {
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
        for (uint256 i; i < core.length; ++i) {
            assertEq(d.facetAddress(core[i]), address(d), "core selector not self-routed");
        }
        // Diamond itself is the sole facet at construction
        address[] memory addrs = d.facetAddresses();
        assertEq(addrs.length, 1);
        assertEq(addrs[0], address(d));
    }

    // ───────── Access control ───────────────────────────────────────────

    function test_diamondCut_revertsNonOwner() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        vm.expectRevert(Diamond.NotOwner.selector);
        vm.prank(ALICE);
        d.diamondCut(cuts, address(0), "");
    }

    function test_transferOwnership_revertsNonOwner() public {
        vm.expectRevert(Diamond.NotOwner.selector);
        vm.prank(ALICE);
        d.transferOwnership(BOB);
    }

    function test_cancelOwnershipTransfer_revertsNonOwner() public {
        vm.expectRevert(Diamond.NotOwner.selector);
        vm.prank(ALICE);
        d.cancelOwnershipTransfer();
    }

    // ───────── Add ──────────────────────────────────────────────────────

    function test_add_singleSelector() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);

        vm.expectEmit(true, true, true, true, address(d));
        emit DiamondCut(cuts, address(0), "");

        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");

        assertEq(d.facetAddress(FacetA.a1.selector), address(fa));
        // Route works end-to-end
        (bool ok, bytes memory ret) = address(d).call(abi.encodeWithSelector(FacetA.a1.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 0xa1);
    }

    function test_add_multipleSelectors() public {
        bytes4[] memory sels = new bytes4[](3);
        sels[0] = FacetA.a1.selector;
        sels[1] = FacetA.a2.selector;
        sels[2] = FacetA.a3.selector;

        IDiamondCut.FacetCut[] memory cuts = _multiSelCut(address(fa), IDiamondCut.FacetCutAction.Add, sels);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");

        bytes4[] memory got = d.facetFunctionSelectors(address(fa));
        assertEq(got.length, 3);
    }

    function test_add_revertsZeroFacet() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(0), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        vm.expectRevert(Diamond.FacetCannotBeZero.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_add_revertsFacetIsDiamondItself() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(d), IDiamondCut.FacetCutAction.Add, bytes4(0xdeadbeef));
        vm.expectRevert(Diamond.InvalidFacet.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_add_revertsFacetHasNoCode() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(ALICE, IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.FacetHasNoCode.selector, ALICE));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_add_revertsEmptySelectors() public {
        bytes4[] memory sels = new bytes4[](0);
        IDiamondCut.FacetCut[] memory cuts = _multiSelCut(address(fa), IDiamondCut.FacetCutAction.Add, sels);
        vm.expectRevert(Diamond.NoSelectorsProvided.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_add_revertsZeroSelector() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, bytes4(0));
        vm.expectRevert(Diamond.InvalidSelector.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_add_revertsDuplicateSelector() public {
        IDiamondCut.FacetCut[] memory cuts1 =
            _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts1, address(0), "");

        IDiamondCut.FacetCut[] memory cuts2 =
            _oneSelCut(address(fb), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.SelectorAlreadyExists.selector, FacetA.a1.selector));
        vm.prank(OWNER);
        d.diamondCut(cuts2, address(0), "");
    }

    function test_add_revertsImmutableSelector() public {
        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, IDiamondCut.diamondCut.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.ImmutableSelector.selector, IDiamondCut.diamondCut.selector));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    // ───────── Replace ──────────────────────────────────────────────────

    function test_replace_movesSelector() public {
        // Seed: fa.a1 added
        vm.startPrank(OWNER);
        d.diamondCut(_oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector), address(0), "");
        // Replace: route a1 to fb
        d.diamondCut(_oneSelCut(address(fb), IDiamondCut.FacetCutAction.Replace, FacetA.a1.selector), address(0), "");
        vm.stopPrank();

        assertEq(d.facetAddress(FacetA.a1.selector), address(fb));
        (bool ok, bytes memory ret) = address(d).call(abi.encodeWithSelector(FacetA.a1.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 0xb1);
    }

    function test_replace_revertsZeroFacet() public {
        vm.prank(OWNER);
        d.diamondCut(_oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector), address(0), "");

        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(0), IDiamondCut.FacetCutAction.Replace, FacetA.a1.selector);
        vm.expectRevert(Diamond.FacetCannotBeZero.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_replace_revertsFacetIsDiamondItself() public {
        vm.prank(OWNER);
        d.diamondCut(_oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector), address(0), "");

        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(d), IDiamondCut.FacetCutAction.Replace, FacetA.a1.selector);
        vm.expectRevert(Diamond.InvalidFacet.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_replace_revertsSelectorNotFound() public {
        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Replace, FacetA.a1.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.SelectorNotFound.selector, FacetA.a1.selector));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_replace_revertsSameFacet() public {
        vm.startPrank(OWNER);
        d.diamondCut(_oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector), address(0), "");
        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Replace, FacetA.a1.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.SelectorAlreadyExists.selector, FacetA.a1.selector));
        d.diamondCut(cuts, address(0), "");
        vm.stopPrank();
    }

    function test_replace_revertsImmutableSelector() public {
        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Replace, IOwnership.owner.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.ImmutableSelector.selector, IOwnership.owner.selector));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    // ───────── Remove ───────────────────────────────────────────────────

    function test_remove_singleSelector() public {
        vm.startPrank(OWNER);
        d.diamondCut(_oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector), address(0), "");
        d.diamondCut(_oneSelCut(address(0), IDiamondCut.FacetCutAction.Remove, FacetA.a1.selector), address(0), "");
        vm.stopPrank();

        assertEq(d.facetAddress(FacetA.a1.selector), address(0));
        // Facet was cleaned up since it had no remaining selectors
        address[] memory addrs = d.facetAddresses();
        assertEq(addrs.length, 1); // only the diamond itself
        assertEq(addrs[0], address(d));
    }

    function test_remove_doesNotRemoveFacetIfOtherSelectorsRemain() public {
        bytes4[] memory sels = new bytes4[](2);
        sels[0] = FacetA.a1.selector;
        sels[1] = FacetA.a2.selector;

        vm.startPrank(OWNER);
        d.diamondCut(_multiSelCut(address(fa), IDiamondCut.FacetCutAction.Add, sels), address(0), "");
        d.diamondCut(_oneSelCut(address(0), IDiamondCut.FacetCutAction.Remove, FacetA.a1.selector), address(0), "");
        vm.stopPrank();

        assertEq(d.facetAddress(FacetA.a1.selector), address(0));
        assertEq(d.facetAddress(FacetA.a2.selector), address(fa));
        address[] memory addrs = d.facetAddresses();
        assertEq(addrs.length, 2);
    }

    function test_remove_revertsSelectorNotFound() public {
        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(0), IDiamondCut.FacetCutAction.Remove, FacetA.a1.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.SelectorNotFound.selector, FacetA.a1.selector));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    function test_remove_revertsImmutableSelector() public {
        IDiamondCut.FacetCut[] memory cuts =
            _oneSelCut(address(0), IDiamondCut.FacetCutAction.Remove, IDiamondCut.diamondCut.selector);
        vm.expectRevert(abi.encodeWithSelector(Diamond.ImmutableSelector.selector, IDiamondCut.diamondCut.selector));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), "");
    }

    // ───────── Init delegatecall ────────────────────────────────────────

    function test_init_success_runsDelegatecall() public {
        GoodInit gi = new GoodInit();
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        bytes memory data = abi.encodeWithSelector(GoodInit.init.selector, uint256(0x42));

        vm.expectEmit(false, false, false, true, address(d)); // Initialized event fires in diamond's context
        emit GoodInit.Initialized(0x42);

        vm.prank(OWNER);
        d.diamondCut(cuts, address(gi), data);
    }

    function test_init_revertsIfInitHasNoCode() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);

        vm.expectRevert(abi.encodeWithSelector(Diamond.InitHasNoCode.selector, ALICE));
        vm.prank(OWNER);
        d.diamondCut(cuts, ALICE, hex"deadbeef");
    }

    function test_init_bubblesCustomRevert() public {
        BadInit bi = new BadInit();
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        bytes memory data = abi.encodeWithSelector(BadInit.blow.selector);

        vm.expectRevert(abi.encodeWithSelector(BadInit.InitBoom.selector, "nope"));
        vm.prank(OWNER);
        d.diamondCut(cuts, address(bi), data);
    }

    function test_init_silentRevert_yieldsInitFailed() public {
        BadInit bi = new BadInit();
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        bytes memory data = abi.encodeWithSelector(BadInit.silent.selector);

        vm.expectRevert(Diamond.InitFailed.selector);
        vm.prank(OWNER);
        d.diamondCut(cuts, address(bi), data);
    }

    function test_init_zeroAddress_skipped() public {
        IDiamondCut.FacetCut[] memory cuts = _oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector);
        // Non-empty data is ignored when init == address(0); cut still applies.
        vm.prank(OWNER);
        d.diamondCut(cuts, address(0), hex"deadbeefcafe");
        assertEq(d.facetAddress(FacetA.a1.selector), address(fa));
    }

    // ───────── Two-step ownership ───────────────────────────────────────

    function test_transferOwnership_setsPending_emitsEvent() public {
        vm.expectEmit(true, true, false, false, address(d));
        emit OwnershipTransferStarted(OWNER, ALICE);
        vm.prank(OWNER);
        d.transferOwnership(ALICE);

        assertEq(d.pendingOwner(), ALICE);
        assertEq(d.owner(), OWNER);
    }

    function test_transferOwnership_revertsZeroAddress() public {
        vm.expectRevert(Diamond.ZeroAddress.selector);
        vm.prank(OWNER);
        d.transferOwnership(address(0));
    }

    function test_acceptOwnership_revertsNotPending() public {
        vm.prank(OWNER);
        d.transferOwnership(ALICE);

        vm.expectRevert(Diamond.NotPendingOwner.selector);
        vm.prank(BOB);
        d.acceptOwnership();
    }

    function test_acceptOwnership_transfers() public {
        vm.prank(OWNER);
        d.transferOwnership(ALICE);

        vm.expectEmit(true, true, false, false, address(d));
        emit OwnershipTransferred(OWNER, ALICE);
        vm.prank(ALICE);
        d.acceptOwnership();

        assertEq(d.owner(), ALICE);
        assertEq(d.pendingOwner(), address(0));
    }

    function test_cancelOwnershipTransfer_clearsPending_emitsEvent() public {
        vm.prank(OWNER);
        d.transferOwnership(ALICE);

        vm.expectEmit(true, false, false, false, address(d));
        emit OwnershipTransferCanceled(ALICE);
        vm.prank(OWNER);
        d.cancelOwnershipTransfer();

        assertEq(d.pendingOwner(), address(0));
        assertEq(d.owner(), OWNER);
    }

    function test_acceptOwnership_revertsAfterCancel() public {
        vm.prank(OWNER);
        d.transferOwnership(ALICE);
        vm.prank(OWNER);
        d.cancelOwnershipTransfer();

        vm.expectRevert(Diamond.NotPendingOwner.selector);
        vm.prank(ALICE);
        d.acceptOwnership();
    }

    // ───────── Loupe / routing ──────────────────────────────────────────

    function test_loupe_facetsReflectsState() public {
        vm.prank(OWNER);
        d.diamondCut(_oneSelCut(address(fa), IDiamondCut.FacetCutAction.Add, FacetA.a1.selector), address(0), "");

        IDiamondLoupe.Facet[] memory fs = d.facets();
        assertEq(fs.length, 2);

        // Find fa entry
        bool found;
        for (uint256 i; i < fs.length; ++i) {
            if (fs[i].facetAddress == address(fa)) {
                found = true;
                assertEq(fs[i].functionSelectors.length, 1);
                assertEq(fs[i].functionSelectors[0], FacetA.a1.selector);
            }
        }
        assertTrue(found);
    }

    function test_routing_revertsUnknownSelector() public {
        (bool ok, bytes memory ret) = address(d).call(abi.encodeWithSelector(bytes4(0xdeadbeef)));
        assertFalse(ok);
        bytes4 expectedSel = Diamond.SelectorNotFound.selector;
        assertEq(bytes4(ret), expectedSel);
    }

    function test_receive_revertsOnPlainEth() public {
        (bool ok,) = address(d).call{value: 1 ether}("");
        assertFalse(ok);
    }
}

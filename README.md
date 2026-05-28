# Diamond Proxy

Single-contract [EIP-2535](https://eips.ethereum.org/EIPS/eip-2535) Diamond implementation with an immutable governance core and upgradeable facets.

## Why

Existing Diamond implementations (diamond-1/2/3) split governance across multiple contracts and use position-tracking structs for O(1) selector removal. This implementation keeps everything in a single contract, uses swap-and-pop with a simpler storage layout, and makes core functions truly immutable, not just by convention but enforced on-chain.

## Design

The entire Diamond lives in one contract (`Diamond.sol`, ~293 lines). Core functions (`diamondCut`, all four loupe functions, ERC-165, and two-step ownership) are registered at deploy time and **cannot be added, replaced, or removed** via `diamondCut`. Everything else is upgradeable through facets.

Selector-based routing inherits OpenZeppelin's `Proxy`, overriding `_implementation()` to resolve `msg.sig` against the facet registry. This gives the Diamond a standard proxy fallback without reimplementing low-level assembly.

### Architecture

```
Diamond.sol               Proxy + diamondCut + loupe + ownership (immutable)
DiamondStorage.sol        EIP-7201 namespaced storage layout
interfaces/
  IDiamondCut.sol         EIP-2535 cut interface
  IDiamondLoupe.sol       EIP-2535 loupe interface
  IOwnership.sol          Two-step ownership with cancellation
```

### Key Properties

- **Immutable core**: 11 selectors (cut, 4 loupe, ERC-165, 5 ownership) are locked at construction via `isImmutableSelector` mapping
- **EIP-7201 storage**: Namespaced slot (`erc7201:diamond.proxy.storage`) prevents collisions with facet storage
- **Two-step ownership**: propose, accept, cancel pattern emitting `OwnershipTransferStarted`, `OwnershipTransferred`, and `OwnershipTransferCanceled`
- **Facet validation**: `extcodesize` check, `address(0)` rejection, `bytes4(0)` selector guard, and same-facet replacement prevention
- **Revert bubbling**: Failed `init` delegatecalls propagate the original revert reason
- **Block scanner compatible**: Loupe functions and `address(this)` facet registration allow tools like Louper.dev to introspect the Diamond

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test
```

40 unit tests covering constructor, diamondCut (add/replace/remove), loupe queries, ownership lifecycle, immutability guards, and edge cases.

### Fuzz

```shell
echidna test/echidna/DiamondEchidna.sol --contract DiamondEchidna --config test/echidna/echidna.yaml
```

### Deploy

```solidity
Diamond diamond = new Diamond(ownerAddress);
```

Then add facets via `diamondCut`:

```solidity
IDiamondCut.FacetCut[] memory cuts = new IDiamondCut.FacetCut[](1);
cuts[0] = IDiamondCut.FacetCut({
    facetAddress: address(myFacet),
    action: IDiamondCut.FacetCutAction.Add,
    functionSelectors: selectors
});
Diamond(payable(address(diamond))).diamondCut(cuts, address(0), "");
```

## License

MIT

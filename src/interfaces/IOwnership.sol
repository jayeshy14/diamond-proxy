// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title IOwnership - Two-step ownership transfer interface
/// @notice Ownership management with propose-accept pattern and cancellation
interface IOwnership {
    /// @notice Emitted when a new owner is proposed
    /// @param previousOwner Current owner who initiated the transfer
    /// @param newOwner Proposed new owner
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when ownership transfer is finalized
    /// @param previousOwner The outgoing owner
    /// @param newOwner The new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Emitted when a pending ownership transfer is canceled
    /// @param previousPending The pending owner that was cleared
    event OwnershipTransferCanceled(address indexed previousPending);

    /// @notice Propose a new owner (must be accepted by the new owner)
    /// @param newOwner Address of the proposed new owner
    function transferOwnership(address newOwner) external;

    /// @notice Accept a pending ownership transfer (callable only by pending owner)
    function acceptOwnership() external;

    /// @notice Cancel a pending ownership transfer (callable only by current owner)
    function cancelOwnershipTransfer() external;

    /// @notice Returns the current owner
    /// @return The owner address
    function owner() external view returns (address);

    /// @notice Returns the pending owner awaiting acceptance
    /// @return The pending owner address (address(0) if none)
    function pendingOwner() external view returns (address);
}

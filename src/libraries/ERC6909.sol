// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title ERC6909
 * @notice Minimal multi-token standard implementation
 * @dev Based on EIP-6909: https://eips.ethereum.org/EIPS/eip-6909
 *      Similar to ERC1155 but simpler and more gas efficient
 */
abstract contract ERC6909 {
    // ============ Events ============

    /// @notice Emitted when tokens are transferred
    event Transfer(
        address caller,
        address indexed from,
        address indexed to,
        uint256 indexed id,
        uint256 amount
    );

    /// @notice Emitted when operator approval is set
    event OperatorSet(
        address indexed owner,
        address indexed operator,
        bool approved
    );

    /// @notice Emitted when spending approval is set
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id,
        uint256 amount
    );

    // ============ Errors ============

    error InsufficientBalance();
    error InsufficientAllowance();

    // ============ State ============

    /// @notice Token balances: owner => id => balance
    mapping(address => mapping(uint256 => uint256)) public balanceOf;

    /// @notice Spending allowances: owner => spender => id => amount
    mapping(address => mapping(address => mapping(uint256 => uint256))) public allowance;

    /// @notice Operator approvals: owner => operator => approved
    mapping(address => mapping(address => bool)) public isOperator;

    // ============ ERC6909 Functions ============

    /// @notice Transfer tokens from caller to recipient
    /// @param receiver The recipient address
    /// @param id The token ID
    /// @param amount The amount to transfer
    /// @return True if successful
    function transfer(
        address receiver,
        uint256 id,
        uint256 amount
    ) public virtual returns (bool) {
        if (balanceOf[msg.sender][id] < amount) revert InsufficientBalance();

        balanceOf[msg.sender][id] -= amount;
        balanceOf[receiver][id] += amount;

        emit Transfer(msg.sender, msg.sender, receiver, id, amount);
        return true;
    }

    /// @notice Transfer tokens from one address to another
    /// @param sender The sender address
    /// @param receiver The recipient address
    /// @param id The token ID
    /// @param amount The amount to transfer
    /// @return True if successful
    function transferFrom(
        address sender,
        address receiver,
        uint256 id,
        uint256 amount
    ) public virtual returns (bool) {
        if (sender != msg.sender && !isOperator[sender][msg.sender]) {
            uint256 currentAllowance = allowance[sender][msg.sender][id];
            if (currentAllowance != type(uint256).max) {
                if (currentAllowance < amount) revert InsufficientAllowance();
                allowance[sender][msg.sender][id] = currentAllowance - amount;
            }
        }

        if (balanceOf[sender][id] < amount) revert InsufficientBalance();

        balanceOf[sender][id] -= amount;
        balanceOf[receiver][id] += amount;

        emit Transfer(msg.sender, sender, receiver, id, amount);
        return true;
    }

    /// @notice Approve spender to spend tokens
    /// @param spender The spender address
    /// @param id The token ID
    /// @param amount The amount to approve
    /// @return True if successful
    function approve(
        address spender,
        uint256 id,
        uint256 amount
    ) public virtual returns (bool) {
        allowance[msg.sender][spender][id] = amount;
        emit Approval(msg.sender, spender, id, amount);
        return true;
    }

    /// @notice Set operator approval for all tokens
    /// @param operator The operator address
    /// @param approved Whether to approve or revoke
    /// @return True if successful
    function setOperator(
        address operator,
        bool approved
    ) public virtual returns (bool) {
        isOperator[msg.sender][operator] = approved;
        emit OperatorSet(msg.sender, operator, approved);
        return true;
    }

    // ============ Internal Functions ============

    /// @notice Mint tokens to an address
    /// @param to The recipient address
    /// @param id The token ID
    /// @param amount The amount to mint
    function _mint(address to, uint256 id, uint256 amount) internal virtual {
        balanceOf[to][id] += amount;
        emit Transfer(msg.sender, address(0), to, id, amount);
    }

    /// @notice Burn tokens from an address
    /// @param from The address to burn from
    /// @param id The token ID
    /// @param amount The amount to burn
    function _burn(address from, uint256 id, uint256 amount) internal virtual {
        if (balanceOf[from][id] < amount) revert InsufficientBalance();
        balanceOf[from][id] -= amount;
        emit Transfer(msg.sender, from, address(0), id, amount);
    }

    // ============ ERC165 ============

    /// @notice Check interface support
    /// @param interfaceId The interface ID to check
    /// @return True if supported
    function supportsInterface(bytes4 interfaceId) public view virtual returns (bool) {
        return interfaceId == 0x01ffc9a7  // ERC165
            || interfaceId == 0x0f632fb3; // ERC6909
    }
}

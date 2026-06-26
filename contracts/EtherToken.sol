// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract EtherToken is ERC20, ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 public constant MAX_SUPPLY = 21_000_000_000_000 * 1e18; // 21 trillion
    uint256 public constant GENESIS_ALLOCATION = MAX_SUPPLY * 90 / 100; // 90% genesis
    uint256 public immutable genesisEnd;

    constructor(address genesisRecipient, uint256 genesisDuration)
        ERC20("Ethercoin", "ETHER")
    {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(BURNER_ROLE, msg.sender);

        // Mint genesis allocation
        _mint(genesisRecipient, GENESIS_ALLOCATION);
        genesisEnd = block.timestamp + genesisDuration;
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyRole(BURNER_ROLE) {
        _burn(account, amount);
    }
}

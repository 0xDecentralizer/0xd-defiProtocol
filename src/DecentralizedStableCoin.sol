// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.30;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Decentralized Stable Coin
 * @author Mohammad Mahdi Keshavarz - AKA 0xdecentralizer
 * @notice Decentralized stable coin pegged to USD via collateralized minting mechanism.
 * @dev Inheritable ERC20 token controlled by DSCEngine for minting/burning operations.
 *
 * Design:
 * - Collateral: Exogenous (external assets)
 * - Stability Mechanism: Decentralized (Algorithmic)
 * - Peg: USD (via DSCEngine)
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    // Errors
    error DecentralizedStableCoin__ZeroAddressNotAccepted();
    error DecentralizedStableCoin__AmountMustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExeedBalance();

    // constructor
    constructor(address initialOwner) ERC20("Decentralized Stable Coin", "DSC") Ownable(initialOwner) {}

    // receive/fallback function (if exists)

    // external
    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = address(this).balance;
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }
        if (_amount > balance) {
            revert DecentralizedStableCoin__BurnAmountExeedBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecentralizedStableCoin__ZeroAddressNotAccepted();
        }
        if (_amount <= 0) {
            revert DecentralizedStableCoin__AmountMustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}

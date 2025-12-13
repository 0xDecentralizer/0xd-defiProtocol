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

/**
 * @title DSCEngine
 * @author Patrick Collins
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral < the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is based on the MakerDAO DSS system
 */
contract DSCEngine {

    // Errors
    error DSCEngine__NeedsMoreThanZero();

    // Modifiers
    modifier needsMoreThanZero(uint256 amount) {
        _needsMoreThanZero(amount);
        _;
    }

    // External Functions
    /**
     * @notice Deposits collateral into the DSC system 
     * @param collateralAddress The address of the collateral token to deposit
     * @param amount The amount of collateral to deposit
     */
    function depositCollateral(address collateralAddress, uint256 amount) external needsMoreThanZero(amount) {}

    function depositCollateralAndMintIt() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDsc() external {}

    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    function _needsMoreThanZero(uint256 amount) internal pure {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
    }
}

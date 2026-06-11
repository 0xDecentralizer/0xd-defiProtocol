// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is StdInvariant, Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;

    uint256 constant DEPOSIT_AMOUNT = 100_000 ether;
    uint256 constant REDEEM_AMOUNT = 10_000 ether;
    uint256 constant MINT_AMOUNT = 1_000_000 ether;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dsce = _dsce;
        dsc = _dsc;
        config = _config;
        (wethUsdPriceFeed, wbtcUsdPriceFeed ,weth, wbtc,) = config.activeNetworkConfig();
    } 

    function depositCollateral(uint256 collateralSeed, uint256 amountToDeposit) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        _depositCollateral(collateral, amountToDeposit);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountToRedeem) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        _depositCollateral(collateral, amountToRedeem);
        _redeemCollateral(collateral, amountToRedeem);
    }

    function mintDsc(uint256 amountToMint, uint256 collateralSeed) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        _depositCollateral(collateral, amountToMint);
        _mintDsc(amountToMint);
    }

    function _getCollateralBySeed(uint256 seed) private view returns (address collateral) {
        collateral = seed % 2 == 0 ? weth : wbtc;
    }

    function _depositCollateral(address collateral, uint256 amountToDeposit) private {
        amountToDeposit = bound(amountToDeposit, 1, DEPOSIT_AMOUNT);
        ERC20Mock(collateral).mint(address(this), amountToDeposit);
        ERC20Mock(collateral).approve(address(dsce), amountToDeposit);
        dsce.depositCollateral(collateral, amountToDeposit);
    }

    function _redeemCollateral(address collateral, uint256 amountToRedeem) private {
        amountToRedeem = bound(amountToRedeem, 1, REDEEM_AMOUNT);
        dsce.redeemCollateral(collateral, amountToRedeem);
    }

    function _mintDsc(uint256 amountToMint) private {
        amountToMint = bound(amountToMint, 1, MINT_AMOUNT);
        dsce.mintDsc(amountToMint);
    }
}
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

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dsce = _dsce;
        dsc = _dsc;
        config = _config;
        (wethUsdPriceFeed, wbtcUsdPriceFeed ,weth, wbtc,) = config.activeNetworkConfig();
    } 

    function depositCollateral(uint256 collateralSeed, uint256 amount) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        amount = bound(amount, 1, 100 ether);
        ERC20Mock(collateral).mint(address(this), amount);
        ERC20Mock(collateral).approve(address(dsce), amount);
        dsce.depositCollateral(collateral, amount);
    }

    function _getCollateralBySeed(uint256 seed) private view returns (address collateral) {
        collateral = seed % 2 == 0 ? weth : wbtc;
    }
}
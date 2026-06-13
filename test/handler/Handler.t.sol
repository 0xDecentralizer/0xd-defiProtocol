// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    address[] public actors;
    address internal currentActor;

    uint256 constant MAX_DEPOSIT_AMOUNT = 100_000 ether;
    uint256 constant MAX_REDEEM_AMOUNT = 10_000 ether;
    uint256 constant MAX_MINT_AMOUNT = 1_000_000 ether;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dsce = _dsce;
        dsc = _dsc;
        config = _config;
        (wethUsdPriceFeed, wbtcUsdPriceFeed ,weth, wbtc,) = config.activeNetworkConfig();

        for(uint256 i = 0; i < 100; i++) actors.push(makeAddr(string(abi.encodePacked("actor", i))));
    }

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function depositCollateral(uint256 actorSeed, uint256 collateralSeed, uint256 amountToDeposit) useActor(actorSeed) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        amountToDeposit = bound(amountToDeposit, 1, MAX_DEPOSIT_AMOUNT);
        ERC20Mock(collateral).mint(currentActor, amountToDeposit);
        ERC20Mock(collateral).approve(address(dsce), amountToDeposit);
        dsce.depositCollateral(collateral, amountToDeposit);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountToRedeem, uint256 amountToDeposit) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        amountToRedeem = bound(amountToRedeem, 1, MAX_REDEEM_AMOUNT);
        amountToDeposit = bound(amountToDeposit, amountToRedeem, MAX_DEPOSIT_AMOUNT);
        _depositCollateral(collateral, amountToDeposit);
        _redeemCollateral(collateral, amountToRedeem);
    }

    function mintDsc(uint256 collateralSeed, uint256 amountToMint) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        amountToMint = bound(amountToMint, 1, MAX_MINT_AMOUNT);
        _depositCollateral(collateral, amountToMint);
        _mintDsc(amountToMint);
    }
    
    function burnDsc(uint256 collateralSeed, uint256 amountToMint, uint256 amountToBurn) public {
        address collateral = _getCollateralBySeed(collateralSeed);
        amountToMint = bound(amountToMint, 1, MAX_MINT_AMOUNT);
        amountToBurn = bound(amountToBurn, 1, amountToMint);
        _depositCollateral(collateral, amountToMint);
        _mintDsc(amountToMint);
        _burnDsc(amountToBurn);
    }

    function _getCollateralBySeed(uint256 seed) private view returns (address collateral) {
        collateral = seed % 2 == 0 ? weth : wbtc;
    }

    function _depositCollateral(address collateral, uint256 amountToDeposit) private {
    }

    function _redeemCollateral(address collateral, uint256 amountToRedeem) private {
        dsce.redeemCollateral(collateral, amountToRedeem);
    }

    function _mintDsc(uint256 amountToMint) private {
        dsce.mintDsc(amountToMint);
    }

    function _burnDsc(uint256 amountToBurn) private {
        ERC20Mock(address(dsc)).approve(address(dsce), amountToBurn);
        dsce.burnDsc(amountToBurn);
    }
}
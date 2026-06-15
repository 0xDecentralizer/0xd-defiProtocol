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
    address[] public actorsWithCollateral;
    address internal currentActor;
    mapping(address => mapping(address => uint256)) public collateralDeposited;
    mapping(address => uint256) public dscMinted;

    uint256 constant MAX_DEPOSIT_AMOUNT = type(uint32).max;

    uint256 public ghost_depositCalled;
    uint256 public ghost_redeemCalled;
    uint256 public ghost_mintCalled;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc, HelperConfig _config) {
        dsce = _dsce;
        dsc = _dsc;
        config = _config;
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();

        for (uint256 i = 0; i < 100; i++) {
            actors.push(makeAddr(string(abi.encodePacked("actor", i))));
        }
    }

    modifier useActor(uint256 actorSeed) {
        currentActor = actors[bound(actorSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    modifier useActorWithCollateral(uint256 actorSeed) {
        if (actorsWithCollateral.length == 0) {
            vm.startPrank(actors[0]);
            ERC20Mock(weth).mint(actors[0], MAX_DEPOSIT_AMOUNT);
            ERC20Mock(weth).approve(address(dsce), MAX_DEPOSIT_AMOUNT);
            dsce.depositCollateral(weth, MAX_DEPOSIT_AMOUNT);
            vm.stopPrank();
            actorsWithCollateral.push(actors[0]);
        }
        currentActor = actorsWithCollateral[bound(actorSeed, 0, actorsWithCollateral.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    function depositCollateral(uint256 actorSeed, uint256 collateralSeed, uint256 amountToDeposit)
        public
        useActor(actorSeed)
    {
        address collateral = _getCollateralBySeed(collateralSeed);
        amountToDeposit = bound(amountToDeposit, 1, MAX_DEPOSIT_AMOUNT);

        ERC20Mock(collateral).mint(currentActor, amountToDeposit);
        ERC20Mock(collateral).approve(address(dsce), amountToDeposit);
        dsce.depositCollateral(collateral, amountToDeposit);

        if (collateralDeposited[currentActor][weth] == 0 && collateralDeposited[currentActor][wbtc] == 0) {
            actorsWithCollateral.push(currentActor);
        }
        collateralDeposited[currentActor][collateral] += amountToDeposit;
        ghost_depositCalled++;
    }

    function redeemCollateral(uint256 actorSeed, uint256 collateralSeed, uint256 amountToRedeem)
        public
        useActorWithCollateral(actorSeed)
    {
        address collateral = _getCollateralBySeed(collateralSeed);

        uint256 maxRedeemAmount = _getSafeRedeemAmount(currentActor, collateral);
        
        amountToRedeem = bound(amountToRedeem, 0, maxRedeemAmount);
        if (amountToRedeem == 0) return;
        dsce.redeemCollateral(collateral, amountToRedeem);
        ghost_redeemCalled++;
    }

    function mintDsc(uint256 actorSeed, uint256 amountToMint) public useActorWithCollateral(actorSeed) {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = dsce.getAccountInformation(currentActor);
        int256 maxMintAmount = (int256(totalCollateralValue) / 2) - int256(totalDscMinted);
        vm.assume(maxMintAmount > 0);

        amountToMint = bound(amountToMint, 1, uint256(maxMintAmount));
        dsce.mintDsc(amountToMint);
        ghost_mintCalled++;
    }

    function _getCollateralBySeed(uint256 seed) private view returns (address collateral) {
        collateral = seed % 2 == 0 ? weth : wbtc;
    }

    function _getSafeRedeemAmount(address actor, address collateral) private returns (uint256) {
        (uint256 totalDscMinted, uint256 totalCollateralValue) = dsce.getAccountInformation(currentActor);
        uint256 maxValueToRedeem = (totalCollateralValue / 2) - totalDscMinted;

        uint256 primaryAmount = dsce.getCollateralAmountFromUsdValue(collateral, maxValueToRedeem);
        uint256 actorCollateralBalance = dsce.getCollateralDeposited(currentActor, collateral);
        if (actorCollateralBalance >= primaryAmount) {
            return primaryAmount;
        }
        return actorCollateralBalance;
    }
}

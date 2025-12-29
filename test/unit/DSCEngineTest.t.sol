// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    address immutable USER = makeAddr("user 1");

    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;
    HelperConfig config;
    address wethUsdPriceFeed;
    address wbtcUsdPriceFeed;
    address weth;
    address wbtc;
    
    modifier userDeposited10Eth() {
        ERC20Mock(weth).mint(USER, 10 ether);
        vm.startPrank(USER);
        IERC20(weth).approve(address(dscEngine), 10 ether);
        dscEngine.depositCollateral(weth, 10 ether);
        vm.stopPrank();

        _;
    }

    modifier userMint100DscToken() {
        vm.prank(USER);
        dscEngine.mintDsc(100e8);
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dscToken, dscEngine, config) = deployer.run();
        (wethUsdPriceFeed, wbtcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
    }
    
    /**
     * @dev Check the initial state of contract after deploy.
     */
    function testCheckInitialState() public view {
        address priceFeedAddress0 = wethUsdPriceFeed;
        address priceFeedAddress1 = wbtcUsdPriceFeed;
        address dscTokenAddress = address(dscToken);

        assertEq(dscEngine.getPriceFeed(weth), priceFeedAddress0);
        assertEq(dscEngine.getPriceFeed(wbtc), priceFeedAddress1);
        assertEq(dscEngine.getDscTokenAddress(), dscTokenAddress);
    }

    /**
     * @dev Get the USD value of a token and check the correctness.
     */
    function testGetUsdValue() public {
        uint256 amount = 3;
        uint256 expectedUsd = 9_000;
        uint256 actualUsd = dscEngine.getUsdValue(weth, amount);

        assertEq(expectedUsd, actualUsd, "Invalid USD calculation!");
    }
    
    /**
     * @dev Test health factor for a user that deposited 10 ether and
     *      dosen't have mint any dsc token yet.
     */
    function testgetHealthFactor() public userDeposited10Eth {
        uint256 expectedHealthFactor = type(uint256).max;
        uint256 actualHealthFacotr = dscEngine.getHealthFactor(USER);

        assertEq(expectedHealthFactor, actualHealthFacotr);
    }
}
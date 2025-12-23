// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {MockCollateral} from "../script/mocks/wbtcMock.sol";

// (address[] memory collateralAddresses, address[] memory priceFeedAddresses, address dscTokenAddress)
contract DeployDSC is Script {
    DSCEngine dscEngine;
    DecentralizedStableCoin dscToken;
    MockCollateral wBTC;
    MockCollateral wETH;

    address btcPriceFeed = 0x5fb1616F78dA7aFC9FF79e0371741a747D2a7F22;
    address ethPriceFeed = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    address[] collateralAddresses;
    address[] priceFeedAddresses = [btcPriceFeed, ethPriceFeed];
    address dscTokenAddress;

    address constant PLAYER = address(0x100);

    function run() public {
        vm.startBroadcast();
        dscToken = new DecentralizedStableCoin(msg.sender);
        wBTC = new MockCollateral();
        wETH = new MockCollateral();
        collateralAddresses.push(address(wBTC));
        collateralAddresses.push(address(wETH));

        dscEngine = new DSCEngine(collateralAddresses, priceFeedAddresses, dscTokenAddress);
        console.log("Collaterals:");
        console.log(collateralAddresses[0]);
        console.log(collateralAddresses[1]);
        console.log("Price Feeds:");
        console.log(priceFeedAddresses[0]);
        console.log(priceFeedAddresses[1]);

        wBTC.mint(msg.sender, 10 ether);
        wBTC.approve(address(dscEngine), type(uint256).max);
        dscEngine.depositCollateral(address(wBTC), 1 ether);
        console.log("Deposited 1 wBTC as collateral");
        uint256 hf = dscEngine.getHealthFactor(msg.sender);
        console.log("Health Factor:", hf);
        uint256 btcValue = dscEngine.getUsdValue(btcPriceFeed, 1);
        console.log("1 wBTC is worth $", btcValue / 1e8);

        vm.stopBroadcast();
        dscTokenAddress = address(dscToken);
    }
}
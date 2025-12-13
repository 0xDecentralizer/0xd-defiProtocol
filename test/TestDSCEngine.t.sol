// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";

contract TestDSCEngine is Test {
    address immutable OWNER = makeAddr("OWNER");
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    address[] collateralAdresses = [address(bytes20("eth")), address(bytes20("btc"))];
    address[] priceFeedAddresses = [address(bytes20("ethP")), address(bytes20("btcP"))];

    function setUp() public {
        dsc = new DecentralizedStableCoin(OWNER);
        dscEngine = new DSCEngine(collateralAdresses, priceFeedAddresses, address(dsc));
    }

    function test_CheckInitialState() public view {
        address priceFeedAddress0 = priceFeedAddresses[0];
        address priceFeedAddress1 = priceFeedAddresses[1];
        address dscToken = address(dsc);

        assertEq(dscEngine.getPriceFeed(collateralAdresses[0]), priceFeedAddress0);
        assertEq(dscEngine.getPriceFeed(collateralAdresses[1]), priceFeedAddress1);
        assertEq(dscEngine.getDscTokenAddress(), dscToken);
    }

    function testDepositWithInvalidArguments() public {

    }

}
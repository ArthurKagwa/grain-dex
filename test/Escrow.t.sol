// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EscrowSafe.sol";
import "../node_modules/openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract EscrowUnit is Test {
    ERC20PresetMinterPauser usdc;
    EscrowSafe escrow;

    address buyer = vm.addr(1);
    address farmer = vm.addr(2);
    address transporter = vm.addr(3);
    address platform = vm.addr(4);

    function setUp() public {
        usdc = new ERC20PresetMinterPauser("MockUSDC","mUSDC");
        escrow = new EscrowSafe(IERC20(address(usdc)));
        usdc.mint(buyer, 1e24);                // 1 000 000 mUSDC
        vm.startPrank(buyer);
        usdc.approve(address(escrow), 1e21);    // 1 000 mUSDC
        bytes32 id = keccak256("batch-1");
        escrow.lock(id, farmer, transporter, platform, 1e21);
        vm.stopPrank();
    }

    function testReleaseWithTwoSignatures() public {
        bytes32 id = keccak256("batch-1");
        vm.prank(farmer);
        escrow.farmerSign(id);                       // buyer signs
        vm.prank(transporter);
        escrow.transporterSign(id);
        vm.prank(buyer);
        escrow.buyerSign(id);                       // farmer signs -> should release

        assertEq(usdc.balanceOf(farmer), 97e18);      // 97 % (assuming 18 decimals)
        assertEq(usdc.balanceOf(platform), 3e18);     // 3 %
    }
}

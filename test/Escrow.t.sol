// test/Escrow.t.sol
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/EscrowSafe.sol";
import "../node_modules/openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract EscrowV3Test is Test {
    ERC20PresetMinterPauser usdc;
    EscrowSafe escrow;

    address buyer       = vm.addr(1);
    address farmer      = vm.addr(2);
    address transporter = vm.addr(3);
    address platform    = vm.addr(4);

    // grain price 1 000 tokens, freight 325 tokens
    uint256 constant FARMER_PAY   = 1_000e18;
    uint256 constant FREIGHT_PAY  =   325e18;
    uint256 constant TOTAL_LOCKED = FARMER_PAY + FREIGHT_PAY;     // 1 325e18
    uint256 constant PLATFORM_FEE = (TOTAL_LOCKED * 3) / 100;     //   39.75e18

    function setUp() public {
        usdc   = new ERC20PresetMinterPauser("MockUSDC", "mUSDC");
        escrow = new EscrowSafe(IERC20(address(usdc)));

        // fund buyer
        usdc.mint(buyer, 2_000e18);
        vm.startPrank(buyer);
        usdc.approve(address(escrow), TOTAL_LOCKED + PLATFORM_FEE);

        // lock funds
        bytes32 id = keccak256("batch-1");
        escrow.lock(
            id,
            farmer,
            transporter,
            platform,
            FARMER_PAY,
            FREIGHT_PAY    // removed the extra parameter
        );
        vm.stopPrank();
    }

    function testFullWorkflow() public {
        bytes32 id = keccak256("batch-1");

        // farmer signs
        vm.prank(farmer);
        escrow.farmerSign(id);

        // transporter signs
        vm.prank(transporter);
        escrow.transporterSign(id);

        // buyer signs
        vm.prank(buyer);
        escrow.buyerSign(id);

        // platform finalises
        vm.prank(platform);
        escrow.finalize(id);

        // asserts
        assertEq(usdc.balanceOf(farmer),      FARMER_PAY,  "farmer paid");
        assertEq(usdc.balanceOf(transporter), FREIGHT_PAY, "transporter paid");
        assertEq(usdc.balanceOf(platform),    PLATFORM_FEE,"platform fee");
        assertEq(usdc.balanceOf(address(escrow)), 0,       "escrow empty");
    }
}

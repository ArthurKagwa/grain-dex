// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Kasoli‑ku‑Mukutu EscrowSafe (v3)
 * @notice 4‑party escrow that now splits the payout three‑ways:
 *         • **Farmer**  – commodity price
 *         • **Transporter** – freight quote (per‑kg‑km oracle)
 *         • **Platform** – 3 % service fee
 *
 * Workflow (unchanged):
 *   1️⃣ Farmer signs at warehouse ➜ produce released
 *   2️⃣ Transporter signs on pick‑up ➜ in transit
 *   3️⃣ Buyer signs on delivery ➜ accepted
 *   4️⃣ Platform calls `finalize()` ➜ funds split & released
 */

import "../node_modules/openzeppelin/contracts/token/ERC20/IERC20.sol";

contract EscrowSafe {
    /* -------------------------------------------------------------------------- */
    /*                                  STORAGE                                   */
    /* -------------------------------------------------------------------------- */

    struct Deal {
        address buyer;
        address farmer;
        address transporter;
        address platform;
        uint256 farmerAmt;      // commodity value (18 dec)
        uint256 transporterAmt; // freight value  (18 dec)
        uint8   sigMask;        // 0x1 buyer, 0x2 farmer, 0x4 transporter
        bool    platformAck;    // platform finalised?
    }

    IERC20 public immutable token;
    mapping(bytes32 => Deal) public deals; // key = keccak256(batchId)

    /* -------------------------------------------------------------------------- */
    /*                               CONSTRUCTOR                                  */
    /* -------------------------------------------------------------------------- */

    constructor(IERC20 _token) {
        token = _token;
    }

    /* -------------------------------------------------------------------------- */
    /*                               ESCROW LOGIC                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Buyer locks **farmer + transporter + 3 % platform** into the contract.
     */
    function lock(
        bytes32 id,
        address farmer,
        address transporter,
        address platform,
        uint256 farmerAmt,
        uint256 transporterAmt
    ) external {
        require(deals[id].farmer == address(0), "deal exists");
        uint256 fee = ((farmerAmt + transporterAmt) * 3) / 100; // 3 % platform fee
        uint256 total = farmerAmt + transporterAmt + fee;
        token.transferFrom(msg.sender, address(this), total);

        deals[id] = Deal({
            buyer: msg.sender,
            farmer: farmer,
            transporter: transporter,
            platform: platform,
            farmerAmt: farmerAmt,
            transporterAmt: transporterAmt,
            sigMask: 0,
            platformAck: false
        });
    }

    /* ---------------------------- role signatures ---------------------------- */

    function farmerSign(bytes32 id) external { _roleSign(id, 1 << 1, "!farmer", deals[id].farmer); }
    function transporterSign(bytes32 id) external { _roleSign(id, 1 << 2, "!trans", deals[id].transporter); }
    function buyerSign(bytes32 id) external {
        Deal storage d = deals[id];
        require(msg.sender == d.buyer, "!buyer");
        require(_hasBit(d.sigMask, 0x6), "not in transit"); // farmer + transporter
        _setBit(d, 1 << 0);
    }

    /* ----------------------------- finalisation ------------------------------ */

    function finalize(bytes32 id) external {
        Deal storage d = deals[id];
        require(msg.sender == d.platform, "!platform");
        require(!_isPaidOut(d), "paid");
        require(_hasBit(d.sigMask, 0x7), "missing sigs");
        d.platformAck = true;
        _payout(id);
    }

    /* -------------------------------------------------------------------------- */
    /*                                INTERNALS                                   */
    /* -------------------------------------------------------------------------- */

    function _roleSign(bytes32 id, uint8 bit, string memory err, address mustBe) internal {
        Deal storage d = deals[id];
        require(msg.sender == mustBe, err);
        _setBit(d, bit);
    }

    function _setBit(Deal storage d, uint8 bit) internal { d.sigMask |= bit; }
    function _hasBit(uint8 mask, uint8 bits) internal pure returns (bool) { return (mask & bits) == bits; }
    function _isPaidOut(Deal storage d) internal view returns (bool) { return d.farmerAmt == 0 && d.transporterAmt == 0; }

    function _payout(bytes32 id) internal {
        Deal storage d = deals[id];
        require(d.platformAck, "no ack");

        uint256 fee = ((d.farmerAmt + d.transporterAmt) * 3) / 100;

        uint256 farmerTake      = d.farmerAmt;
        uint256 transporterTake = d.transporterAmt;
        uint256 platformTake    = fee;

        // zero state before transfers (re‑entrancy guard)
        d.farmerAmt = 0;
        d.transporterAmt = 0;

        token.transfer(d.farmer, farmerTake);
        token.transfer(d.transporter, transporterTake);
        token.transfer(d.platform, platformTake);
    }
}

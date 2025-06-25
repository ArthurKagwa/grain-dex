// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Kasoli‑ku‑Mukutu EscrowSafe (v2)
 * @notice Holds buyer funds until the physical hand‑off sequence is completed *and* the neutral
 *         platform operator resolves/acknowledges any disputes.  Funds move only when:
 *
 *         1️⃣ Farmer signs at the warehouse  → produce released to transporter.
 *         2️⃣ Transporter signs on pick‑up  → produce officially in transit.
 *         3️⃣ Buyer signs on delivery       → produce accepted.
 *         4️⃣ Platform calls `finalize()`   → releases funds to farmer (+ platform fee).
 *
 *         This design removes unattended timeouts: auto‑release is *manual* and can only be
 *         triggered by the designated platform address once conflicts (if any) are settled.
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
        address platform;    // neutral 4th party
        uint256 amount;      // escrowed stable‑coin (18 decimals)
        uint8   sigMask;     // bitmask: 0x1 buyer, 0x2 farmer, 0x4 transporter
        bool    platformAck; // has platform called finalize?
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
     * @dev Buyer locks funds when order is placed.
     */
    function lock(
        bytes32 id,
        address farmer,
        address transporter,
        address platform,
        uint256 amount
    ) external {
        require(deals[id].amount == 0, "deal exists");
        token.transferFrom(msg.sender, address(this), amount);
        deals[id] = Deal({
            buyer: msg.sender,
            farmer: farmer,
            transporter: transporter,
            platform: platform,
            amount: amount,
            sigMask: 0,
            platformAck: false
        });
    }

    /**
     * @dev Farmer signs at the warehouse – first step.
     */
    function farmerSign(bytes32 id) external {
        Deal storage d = deals[id];
        require(msg.sender == d.farmer, "!farmer");
        _setBit(d, 1 << 1); // 0x2
    }

    /**
     * @dev Transporter signs on pick‑up – requires farmer signature first.
     */
    function transporterSign(bytes32 id) external {
        Deal storage d = deals[id];
        require(msg.sender == d.transporter, "!transporter");
        require(_hasBit(d.sigMask, 1 << 1), "farmer first");
        _setBit(d, 1 << 2); // 0x4
    }

    /**
     * @dev Buyer signs on delivery – requires both farmer & transporter signatures.
     */
    function buyerSign(bytes32 id) external {
        Deal storage d = deals[id];
        require(msg.sender == d.buyer, "!buyer");
        require(_hasBit(d.sigMask, (1 << 1) | (1 << 2)), "not in transit");
        _setBit(d, 1 << 0); // 0x1
    }

    /**
     * @dev Final step – platform operator calls after any dispute is settled.
     *      Releases funds if all three role signatures are present.
     */
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

    function _setBit(Deal storage d, uint8 bit) internal {
        d.sigMask |= bit;
    }

    function _hasBit(uint8 mask, uint8 bits) internal pure returns (bool) {
        return (mask & bits) == bits;
    }

    function _isPaidOut(Deal storage d) internal view returns (bool) {
        return d.amount == 0;
    }

    function _payout(bytes32 id) internal {
        Deal storage d = deals[id];
        require(d.platformAck, "no ack");
        uint256 total = d.amount;
        d.amount = 0; // prevent re‑entrancy & double spend

        uint256 platformFee = (total * 3) / 100;          // 3 % fee
        uint256 farmerTake  = total - platformFee;

        token.transfer(d.farmer, farmerTake);
        token.transfer(d.platform, platformFee);
    }
}

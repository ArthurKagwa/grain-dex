// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../node_modules/openzeppelin/contracts/token/ERC1155/ERC1155.sol";

/**
 * @title WarehouseReceipt
 * @dev ERC‑1155 token representing certified grain batches.
 *       Each receipt stores a JSON metadata CID (e.g. moisture, grade)
 *       *and* an image/photo CID for visual verification.
 */
contract WarehouseReceipt is ERC1155 {
    /// @notice incrementing token id counter
    uint256 public lastId;

    // /**
    //  * @param baseURI Pattern for token URI; expects `{id}` substitution.
    //  *               Example: "ipfs://{id}.json" – the dApp can pin a
    //  *               JSON file whose `image` field matches `photoCID`.
    //  */
    constructor() ERC1155("ipfs://{id}.json") {}

    /**
     * @notice Mint a new grain receipt.
     * @param to        Recipient address (usually the farmer).
     * @param weightKg  Quantity represented by this receipt.
     * @param grade     National grade code (e.g. 1‑5).
     * @param metaCID   IPFS CID to JSON metadata (moisture %, foreign matter …).
     * @param photoCID  IPFS CID to a photograph of the batch at the silo.
     * @return id       Newly minted token id.
     */
    function mint(
        address to,
        uint256 weightKg,
        uint8 grade,
        string calldata metaCID,
        string calldata photoCID
    ) external returns (uint256 id) {
        id = ++lastId;
        _mint(to, id, weightKg, "");
        emit Meta(id, grade, metaCID, photoCID);
    }

    /**
     * @dev Emitted once per mint with off‑chain metadata links.
     */
    event Meta(
        uint256 indexed id,
        uint8 grade,
        string metaCID,
        string photoCID
    );
}

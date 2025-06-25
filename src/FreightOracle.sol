pragma solidity ^0.8.24;
contract FreightOracle {
    uint256 public dieselUgxPerLitre;      // updated daily
    function update(uint256 _price) external { dieselUgxPerLitre = _price; }

    function quote(uint256 kg, uint256 km) external view returns (uint256 ugx){
        // constants (tweak later)
        uint256 fuelPerKm = dieselUgxPerLitre / 4;         // 4 km/L
        uint256 maintPerKm = 120;
        uint256 driverPerKm = 150;
        uint256 base = km * (fuelPerKm + maintPerKm + driverPerKm) * 115 / 100; // +15 %
        ugx = base / kg;
    }
}

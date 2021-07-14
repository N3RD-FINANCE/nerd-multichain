pragma solidity 0.6.12;

import "./WithdrawnableBrainz.sol";

// Brainz.
contract Brainz is WithdrawnableBrainz {
    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(
        address _validator
    ) public WithdrawnableBrainz(_validator) {
    }
}

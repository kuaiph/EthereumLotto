pragma solidity ^0.4.10;

contract ProfitSplitter {
    struct BeneficiaryInfo {
        uint currFunds; // Current amount of funds held by this contract for this beneficiary
        uint cut; // Cut of profits (out of 100 total - after token dividends are taken out)
    }

    modifier onlyBeneficiary() {
        require(benMappings[msg.sender].cut > 0);
        _;
    }

    // Address of the contract that provides dividends for token holders.
    address public dividendContractAddress;

    // When enabled, dividends are sent to token holders.
    bool public dividendsEnabled;

    // Percent of profits shared with token holders.
    uint8 dividendShare = 20;
    uint public dividendValue = 0;

    // If we have any wei left after splitting amongst the beneficiaries 
    // use this index to decide who to give the extras to.
    uint8 extraPayoutIndex = 0;

    // Mapping of address to BeneficiaryInfo for quick lookups
    mapping(address => BeneficiaryInfo) public benMappings;

    // List of beneficiary addresses for when we need to iterate through them all.
    address[] public benAddresses;

    function ProfitSplitter() { 

        // Sample addresses.
        benAddresses.push(0xdb57fd6de5faad3f7bee69ee60f874f8cd31cb4a);
        benMappings[benAddresses[0]] = BeneficiaryInfo({
            currFunds: 0,
            cut: 25
        });
        benAddresses.push(0x6a2604420da722503921001458a58f37b1a93f6b);
        benMappings[benAddresses[1]] = BeneficiaryInfo({
            currFunds: 0,
            cut: 25
        });
        benAddresses.push(0x22957c0cb90bb766c5354c727b45fd9c4298e619);
        benMappings[benAddresses[2]] = BeneficiaryInfo({
            currFunds: 0,
            cut: 25
        });
        benAddresses.push(0x7d37113e00bfe1bb9acc83594fa268de8bcf72ed);
        benMappings[benAddresses[3]] = BeneficiaryInfo({
            currFunds: 0,
            cut: 25
        });
    }

    /* withdraw
     *
     * Withdraws all funds owed to the beneficiary calling this function.
     */
    function withdraw() onlyBeneficiary {
        uint currFunds = benMappings[msg.sender].currFunds;
        benMappings[msg.sender].currFunds = 0;

        msg.sender.transfer(currFunds);
    }

    /* withdrawDividends
     *
     * Withdraws dividends owed to the dividend contract
     */
    function withdrawDividends() onlyBeneficiary {
        uint currValue = dividendValue;

        dividendValue = 0;
        
        dividendContractAddress.transfer(currValue);
    }

    /* Default Function
     *
     * Splits incoming funds.
     * First assigns the given percentage to dividends, if enabled,
     * and then splits the remaining funds amongst the beneficiaries.
     */
    function () payable {
        uint value = msg.value;
        uint benValue = value;
        uint totalPaidOut = 0;

        // If we're paying dividends first take the dividend cut...
        if (dividendsEnabled) {
            dividendValue += (msg.value * dividendShare) / uint(100);

            benValue -= dividendValue;
            totalPaidOut += dividendValue;
        }

        // Now pay out to all beneficiaries
        for (uint8 i = 0; i < benAddresses.length; i++) {
            uint share = (benValue * benMappings[benAddresses[i]].cut) / uint(100);

            benMappings[benAddresses[i]].currFunds += share;
            totalPaidOut += share;
        }

        // If there isn't exactly 0 remaining funds left in the msg, add/remove
        // a little from the current beneficiary to be "targeted".
        uint remainingFunds = msg.value - totalPaidOut;
        if (remainingFunds != 0) {
            benMappings[benAddresses[extraPayoutIndex++]].currFunds += remainingFunds;            
        }

        if (extraPayoutIndex >= benAddresses.length) {
            extraPayoutIndex = 0;
        }
    }

    /* enableDividends
     *
     * Turns on dividend payouts.
     */
    function enableDividends() onlyBeneficiary {
        require(dividendContractAddress != 0x0);

        dividendsEnabled = true;
    }

    /* setDividendContractAddress
     * @param _dividendContractAddress - The address of the dividend payment contract.
     *
     * Sets the address of the divident payment contract.
     */
    function setDividendContractAddress(address _dividendContractAddress) onlyBeneficiary {
        dividendContractAddress = _dividendContractAddress;
    }

    /* changeBeneficiaryAddress
     * @param _address - The address to change to.
     *
     * If msg.sender is a benificiary, this changes their benificiary address
     */
    function changeBeneficiaryAddress(address _address) onlyBeneficiary {
        uint existingFunds = benMappings[msg.sender].currFunds;
        uint existingCut = benMappings[msg.sender].cut;

        delete benMappings[msg.sender];

        benMappings[_address] = BeneficiaryInfo({
            currFunds: existingFunds,
            cut: existingCut
        });

        for (uint8 i = 0; i < benAddresses.length; i++) {
            if (benAddresses[i] == msg.sender) {
                benAddresses[i] = _address;
                break;
            }
        }
    }
}